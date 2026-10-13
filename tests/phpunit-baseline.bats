#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../actions/phpunit-baseline/phpunit-baseline.php"

setup() {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p src vendor/acme vendor/bin
    touch src/Foo.php vendor/acme/Lib.php

    cat > phpunit.xml <<'EOF'
<?xml version="1.0"?>
<phpunit><source baseline="phpunit.baseline.xml"/></phpunit>
EOF
    # A config without a baseline must be skipped.
    echo '<?xml version="1.0"?><phpunit/>' > phpunit-other.xml

    # Stub PHPUnit: writes the baseline (with a duplicate) and an event log classifying each deprecation.
    cat > vendor/bin/phpunit <<'EOF'
<?php
foreach ($argv as $arg) {
    if (str_starts_with($arg, '--generate-baseline=')) { $baseline = substr($arg, 20); }
    if (str_starts_with($arg, '--log-events-verbose-text=')) { $events = substr($arg, 26); }
}
file_put_contents($baseline, <<<'XML'
<?xml version="1.0"?>
<files version="1">
 <file path="vendor/acme/Lib.php">
  <line number="3" hash="aaa">
   <issue><![CDATA[Vendor calls vendor]]></issue>
  </line>
  <line number="9" hash="bbb">
   <issue><![CDATA[We call vendor]]></issue>
  </line>
 </file>
 <file path="src/Foo.php">
  <line number="5" hash="ccc">
   <issue><![CDATA[Our own]]></issue>
   <issue><![CDATA[Our own]]></issue>
  </line>
 </file>
</files>
XML);
$cwd = getcwd();
$prefix = '[00:00:01.000000000 / 00:00:00.000000000] [1024 bytes] ';
$indent = str_repeat(' ', strlen($prefix));
file_put_contents($events, implode("\n", [
    $prefix . "Test Triggered PHP Deprecation (T::a, issue triggered by third-party code calling into PHP runtime) in $cwd/vendor/acme/Lib.php:3",
    $indent . 'Vendor calls vendor',
    $prefix . "Test Triggered Deprecation (T::b, issue triggered by first-party code calling into third-party code) in $cwd/vendor/acme/Lib.php:9",
    $indent . 'We call vendor',
    $prefix . "Test Triggered Deprecation (T::c, issue triggered by test code calling into first-party code, suppressed using operator) in $cwd/src/Foo.php:5",
    $indent . 'Our own',
    getenv('STUB_FAILURE') ? $prefix . 'Test Failed (T::d)' : $prefix . 'Test Passed (T::d)',
]) . "\n");
exit(1);
EOF
}

@test "generate keeps first-party and direct deprecations, drops indirect ones and duplicates" {
    run php "$SCRIPT" generate out

    [ "$status" -eq 0 ]
    [ "$(cat out/phpunit.baseline.xml)" = '<?xml version="1.0"?>
<files version="1">
 <file path="src/Foo.php">
  <line number="5" hash="ccc">
   <issue><![CDATA[Our own]]></issue>
  </line>
 </file>
 <file path="vendor/acme/Lib.php">
  <line number="9" hash="bbb">
   <issue><![CDATA[We call vendor]]></issue>
  </line>
 </file>
</files>' ]
}

@test "generate refuses to write a baseline from a failing run" {
    STUB_FAILURE=1 run php "$SCRIPT" generate out

    [ "$status" -eq 1 ]
    [[ "$output" == *"refusing to generate a baseline from a failing run"*"T::d"* ]]
    [ ! -e out/phpunit.baseline.xml ]
}

@test "merge writes the union of baselines generated on several PHP versions" {
    mkdir -p in/8.5 in/8.6
    printf '<?xml version="1.0"?>\n<files version="1"><file path="src/Foo.php"><line number="5" hash="ccc"><issue><![CDATA[Both]]></issue></line></file></files>\n' > in/8.5/phpunit.baseline.xml
    printf '<?xml version="1.0"?>\n<files version="1"><file path="src/Foo.php"><line number="5" hash="ccc"><issue><![CDATA[Both]]></issue><issue><![CDATA[Only on 8.6]]></issue></line></file></files>\n' > in/8.6/phpunit.baseline.xml

    run php "$SCRIPT" merge in/8.5/ in/8.6/

    [ "$status" -eq 0 ]
    [ "$(cat phpunit.baseline.xml)" = '<?xml version="1.0"?>
<files version="1">
 <file path="src/Foo.php">
  <line number="5" hash="ccc">
   <issue><![CDATA[Both]]></issue>
   <issue><![CDATA[Only on 8.6]]></issue>
  </line>
 </file>
</files>' ]
}

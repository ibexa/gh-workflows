<?php

/**
 * Regenerates PHPUnit deprecation baselines without third-party noise.
 *
 *   generate <out-dir>      Runs every phpunit*.xml(.dist) config that declares <source baseline="...">,
 *                           drops entries PHPUnit never reports (only ever triggered by third-party code calling
 *                           into third-party code, or ignored by the test), and writes the result to <out-dir>/<baseline path>.
 *   merge <dir> [<dir>...]  Unions baselines generated on several PHP versions into the working directory.
 *
 * Output is deduplicated and sorted, so regenerating an unchanged project yields no diff.
 */

const KERNEL_CACHE_DIRS = ['ibexa-test-kernel', 'ibexa-test-kernel-build'];
const THIRD_PARTY = ['third-party code', 'PHPUnit', 'PHP runtime'];

exit(main($argv));

function main(array $argv): int
{
    $command = $argv[1] ?? '';
    $dirs = array_slice($argv, 2);

    if ($command === 'generate' && count($dirs) === 1) {
        return generate($dirs[0]);
    }

    if ($command === 'merge' && $dirs !== []) {
        return merge($dirs);
    }

    fwrite(STDERR, "Usage: php phpunit-baseline.php generate <out-dir> | merge <dir> [<dir>...]\n");

    return 2;
}

function generate(string $outDir): int
{
    $configs = array_merge(glob('phpunit*.xml') ?: [], glob('phpunit*.xml.dist') ?: []);
    $generated = 0;

    foreach ($configs as $config) {
        $baseline = baselineOf($config);
        if ($baseline === null) {
            continue;
        }

        // The test kernel caches its container across runs; a warm cache hides deprecations raised while compiling it.
        foreach (KERNEL_CACHE_DIRS as $dir) {
            removeDir(sys_get_temp_dir() . '/' . $dir);
        }

        $events = tempnam(sys_get_temp_dir(), 'phpunit-events-');
        passthru(sprintf(
            // PHP_BINARY, not the shebang's PATH lookup, so PHPUnit runs on the PHP this script was started with.
            '%s -d memory_limit=-1 vendor/bin/phpunit -c %s --no-progress --generate-baseline=%s --log-events-verbose-text=%s',
            escapeshellarg(PHP_BINARY),
            escapeshellarg($config),
            escapeshellarg($baseline),
            escapeshellarg($events),
        ), $exitCode);

        // Exit code 1 is expected: the deprecations being baselined fail the run.
        if ($exitCode > 1 || !is_file($baseline)) {
            fwrite(STDERR, "$config: PHPUnit crashed (exit code $exitCode), baseline not generated.\n");

            return 1;
        }

        [$failures, $unreported] = readEvents($events);
        unlink($events);

        if ($failures !== []) {
            fwrite(STDERR, "$config: refusing to generate a baseline from a failing run:\n  " . implode("\n  ", $failures) . "\n");

            return 1;
        }

        $issues = array_filter(
            readBaseline($baseline),
            static fn (array $issue): bool => !isset($unreported[issueKey(resolve(dirname($baseline), $issue['path']), $issue['line'], $issue['description'])]),
        );

        writeBaseline("$outDir/$baseline", $issues);
        printf("%s: %d entries written to %s\n", $config, count($issues), "$outDir/$baseline");
        ++$generated;
    }

    if ($generated === 0) {
        fwrite(STDERR, "No phpunit*.xml(.dist) config declares <source baseline=\"...\">.\n");

        return 1;
    }

    return 0;
}

function merge(array $dirs): int
{
    $merged = [];

    foreach ($dirs as $dir) {
        if (!is_dir($dir)) {
            fwrite(STDERR, "Not a directory: $dir\n");

            return 1;
        }

        $files = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS));
        foreach ($files as $file) {
            $relative = substr($file->getPathname(), strlen(rtrim($dir, '/')) + 1);
            $merged[$relative] = array_merge($merged[$relative] ?? [], readBaseline($file->getPathname()));
        }
    }

    if ($merged === []) {
        fwrite(STDERR, "No baselines found in: " . implode(', ', $dirs) . "\n");

        return 1;
    }

    foreach ($merged as $baseline => $issues) {
        writeBaseline($baseline, $issues);
        printf("%s: %d entries\n", $baseline, count(dedupe($issues)));
    }

    return 0;
}

function baselineOf(string $config): ?string
{
    $document = new DOMDocument();
    if (!@$document->load($config)) {
        return null;
    }

    $baseline = (new DOMXPath($document))->evaluate('string(/phpunit/source/@baseline)');
    if ($baseline === '') {
        return null;
    }

    $configDir = dirname($config);

    return $configDir === '.' ? $baseline : "$configDir/$baseline";
}

/**
 * @return array{list<string>, array<string, true>} failed tests, and keys of deprecations PHPUnit never reports (indirect or ignored by test)
 */
function readEvents(string $path): array
{
    $failures = [];
    $kinds = [];
    $handle = fopen($path, 'rb');
    $pending = null;

    while (($line = fgets($handle)) !== false) {
        $line = rtrim($line, "\r\n");

        // Event lines carry a "[time / time] [N bytes] " prefix; continuation lines are indented with spaces.
        if (!preg_match('/^\[[^]]+] \[\d+ bytes] (.*)$/', $line, $event)) {
            if ($pending !== null) {
                // First line of the message is enough to tell deprecations apart.
                $key = issueKey($pending['file'], $pending['line'], ltrim($line));
                $kinds[$key][$pending['unreported'] ? 'unreported' : 'other'] = true;
                $pending = null;
            }

            continue;
        }

        $pending = null;
        $event = $event[1];

        if (preg_match('/^Test (?:Failed|Errored) \((.*)\)$/', $event, $match)) {
            $failures[] = $match[1];

            continue;
        }

        if (preg_match('/^Test Triggered (?:PHP )?Deprecation \(.*issue triggered by (.+?) calling into (.+?)(, .*)?\) in (.+):(\d+)$/', $event, $match)) {
            $pending = [
                // Mirrors what PHPUnit ignores at runtime: indirect deprecations, and ones the test itself ignores.
                'unreported' => (in_array($match[1], THIRD_PARTY, true) && in_array($match[2], THIRD_PARTY, true))
                    || str_contains($match[3], 'ignored by test'),
                'file' => $match[4],
                'line' => (int) $match[5],
            ];
        }
    }

    fclose($handle);

    $unreported = [];
    foreach ($kinds as $key => $seen) {
        if (!isset($seen['other'])) {
            $unreported[$key] = true;
        }
    }

    return [$failures, $unreported];
}

function issueKey(string $file, int $line, string $description): string
{
    $file = realpath($file) ?: $file;

    return "$file:$line:" . strtok($description, "\n");
}

function resolve(string $dir, string $path): string
{
    return str_starts_with($path, '/') ? $path : "$dir/$path";
}

/**
 * @return list<array{path: string, line: int, hash: string, description: string}>
 */
function readBaseline(string $path): array
{
    $document = new DOMDocument();
    if (!$document->load($path)) {
        throw new RuntimeException("Cannot read baseline $path");
    }

    $issues = [];
    foreach ($document->getElementsByTagName('file') as $file) {
        foreach ($file->getElementsByTagName('line') as $line) {
            foreach ($line->getElementsByTagName('issue') as $issue) {
                $issues[] = [
                    'path' => $file->getAttribute('path'),
                    'line' => (int) $line->getAttribute('number'),
                    'hash' => $line->getAttribute('hash'),
                    'description' => $issue->textContent,
                ];
            }
        }
    }

    return $issues;
}

function dedupe(array $issues): array
{
    $unique = [];
    foreach ($issues as $issue) {
        $unique[implode("\0", $issue)] = $issue;
    }

    usort($unique, static fn (array $a, array $b): int => [$a['path'], $a['line'], $a['description']] <=> [$b['path'], $b['line'], $b['description']]);

    return $unique;
}

/**
 * Same layout as PHPUnit\Runner\Baseline\Writer.
 */
function writeBaseline(string $path, array $issues): void
{
    $writer = new XMLWriter();
    $writer->openMemory();
    $writer->setIndent(true);
    $writer->startDocument();
    $writer->startElement('files');
    $writer->writeAttribute('version', '1');

    $currentFile = $currentLine = null;
    foreach (dedupe($issues) as $issue) {
        if ($issue['path'] !== $currentFile) {
            if ($currentFile !== null) {
                $writer->endElement();
                $writer->endElement();
            }
            $writer->startElement('file');
            $writer->writeAttribute('path', $issue['path']);
            $currentFile = $issue['path'];
            $currentLine = null;
        }

        if ($issue['line'] !== $currentLine) {
            if ($currentLine !== null) {
                $writer->endElement();
            }
            $writer->startElement('line');
            $writer->writeAttribute('number', (string) $issue['line']);
            $writer->writeAttribute('hash', $issue['hash']);
            $currentLine = $issue['line'];
        }

        $writer->startElement('issue');
        $writer->writeCdata($issue['description']);
        $writer->endElement();
    }

    if ($currentFile !== null) {
        $writer->endElement();
        $writer->endElement();
    }

    $writer->endElement();

    if (!is_dir(dirname($path))) {
        mkdir(dirname($path), 0777, true);
    }

    file_put_contents($path, $writer->outputMemory());
}

function removeDir(string $dir): void
{
    if (!is_dir($dir)) {
        return;
    }

    $entries = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::CHILD_FIRST,
    );
    foreach ($entries as $entry) {
        $entry->isDir() && !$entry->isLink() ? rmdir($entry->getPathname()) : unlink($entry->getPathname());
    }

    rmdir($dir);
}

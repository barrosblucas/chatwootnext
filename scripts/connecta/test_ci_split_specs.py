#!/usr/bin/env python3
"""Regression checks for the CI shard partition; no Rails or services needed."""
import collections
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/connecta/ci_split_specs.sh'


def split(index, total, specs, cwd=ROOT, success=True):
    result = subprocess.run(
        ['bash', str(SCRIPT), str(index), str(total), *specs],
        cwd=cwd, text=True, capture_output=True, check=False,
    )
    if (result.returncode == 0) != success:
        raise AssertionError(result.stderr)
    return [line.split('\t', 1) for line in result.stdout.splitlines()], result.stderr


class SplitSpecsTest(unittest.TestCase):
    def test_full_suite_is_partitioned_once_across_shards(self):
        specs = sorted(str(path.relative_to(ROOT)) for path in (ROOT / 'spec').rglob('*_spec.rb')
                       if not path.relative_to(ROOT).as_posix().startswith('spec/enterprise/'))
        self.assertTrue(specs)
        actual = []
        for index in range(8):
            entries, _ = split(index, 8, specs)
            for kind, path in entries:
                expected = 'f5' if path.startswith(('spec/connecta/', 'spec/requests/connecta/')) else 'common'
                self.assertEqual(kind, expected)
                actual.append(path)
        self.assertEqual(collections.Counter(actual), collections.Counter(specs))
        self.assertIn('spec/requests/connecta/route_inventory_spec.rb', actual)
        self.assertIn('spec/connecta/media_broadcast_sanitizer_spec.rb', actual)

    def test_mixed_selection_and_empty_shard(self):
        specs = ['spec/connecta/runtime_hmac_authenticator_spec.rb',
                 'spec/requests/connecta/route_inventory_spec.rb',
                 'spec/lib/whatsapp/session_contract_spec.rb']
        entries, _ = split(0, 1, specs)
        self.assertEqual(entries, [['f5', specs[0]], ['f5', specs[1]], ['common', specs[2]]])
        self.assertEqual(split(3, 8, specs)[0], [])

    def test_invalid_inputs_fail(self):
        split(1, 1, [], success=False)
        split(0, 1, ['spec/../invalid_spec.rb'], success=False)
        split(0, 1, ['spec/missing_spec.rb'], success=False)

    def test_guarded_spec_outside_runner_allowlist_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            spec = Path(directory) / 'spec/other/guarded_spec.rb'
            spec.parent.mkdir(parents=True)
            spec.write_text('Connecta::G0TargetGuard.verify!\n')
            _, error = split(0, 1, ['spec/other/guarded_spec.rb'], cwd=directory, success=False)
            self.assertIn('outside the F5 runner allowlist', error)


if __name__ == '__main__':
    unittest.main()

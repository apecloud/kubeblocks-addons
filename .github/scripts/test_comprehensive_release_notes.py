#!/usr/bin/env python3
"""
Comprehensive test suite for update_release_notes.py functionality.
This test covers all features including the new detailed summary reporting.
"""

import os
import sys
import tempfile
import shutil
import yaml
from pathlib import Path
from unittest.mock import patch
from io import StringIO

# Add the current directory to the Python path to import the main script
sys.path.insert(0, os.path.dirname(__file__))

from update_release_notes import (
    create_release_entry,
    update_releases_notes,
    find_addon_directories_with_versions,
    parse_chart_version,
    validate_semver,
    is_stable_version,
    check_version_exists,
    check_version_consistency,
    print_detailed_summary,
    save_yaml_file,
    load_yaml_file,
    main
)


class MockArgs:
    """Mock arguments object for testing."""
    def __init__(self, **kwargs):
        self.git_tag = kwargs.get('git_tag', 'v1.2.3')
        self.git_branch = kwargs.get('git_branch', 'release-1.2')
        self.published_at = kwargs.get('published_at', '2025-09-24T12:00:00Z')
        self.commit_sha = kwargs.get('commit_sha', 'abc123def456')
        self.dry_run = kwargs.get('dry_run', False)
        self.include_prerelease = kwargs.get('include_prerelease', False)
        self.check_consistency = kwargs.get('check_consistency', False)


class TestUpdateReleaseNotes:
    """Test suite for update_release_notes.py"""

    def __init__(self):
        self.test_dir = None
        self.addons_dir = None
        self.addons_cluster_dir = None

    def setup_test_environment(self):
        """Create a temporary test environment with mock addon directories."""
        self.test_dir = Path(tempfile.mkdtemp())
        self.addons_dir = self.test_dir / 'addons'
        self.addons_cluster_dir = self.test_dir / 'addons-cluster'

        # Create directory structure
        self.addons_dir.mkdir(parents=True)
        self.addons_cluster_dir.mkdir(parents=True)

        # Create test addons with different scenarios
        test_addons = [
            # Stable versions
            {'name': 'mysql', 'type': 'addons', 'version': '1.0.2', 'stable': True},
            {'name': 'redis', 'type': 'addons', 'version': '1.0.1', 'stable': True},
            {'name': 'redis', 'type': 'addons-cluster', 'version': '1.0.1', 'stable': True},

            # Pre-release versions
            {'name': 'mongodb', 'type': 'addons', 'version': '1.1.0-alpha.0', 'stable': False},
            {'name': 'postgresql', 'type': 'addons-cluster', 'version': '1.1.0-beta.1', 'stable': False},

            # Library chart
            {'name': 'kblib', 'type': 'addons', 'version': '0.1.0', 'stable': True, 'library': True},

            # No version (invalid)
            {'name': 'invalid', 'type': 'addons', 'version': None, 'stable': False},
        ]

        for addon in test_addons:
            addon_path = (self.addons_dir if addon['type'] == 'addons' else self.addons_cluster_dir) / addon['name']
            addon_path.mkdir()

            # Create Chart.yaml
            chart_data = {
                'apiVersion': 'v2',
                'name': addon['name'],
                'type': 'application'
            }

            if addon['version']:
                chart_data['version'] = addon['version']

            chart_file = addon_path / 'Chart.yaml'
            with open(chart_file, 'w') as f:
                yaml.dump(chart_data, f)

            # Create existing releases_notes.yaml for some addons
            if addon['name'] in ['mysql', 'redis']:
                releases_data = {
                    'releases': [
                        {
                            'version': '1.0.0',
                            'released_at': '2025-01-01',
                            'status': 'stable',
                            'git_branch': 'release-1.0',
                            'git_tag': 'v1.0.0',
                            'commit_sha': 'old123'
                        }
                    ]
                }
                releases_file = addon_path / 'releases_notes.yaml'
                with open(releases_file, 'w') as f:
                    yaml.dump(releases_data, f)

    def cleanup_test_environment(self):
        """Clean up the temporary test environment."""
        if self.test_dir and self.test_dir.exists():
            shutil.rmtree(self.test_dir)

    def test_validate_semver(self):
        """Test semantic version validation."""
        print("Testing validate_semver...")

        valid_versions = [
            "1.0.0", "1.2.3", "1.0.0-alpha.0", "1.1.0-beta.1", "2.0.0-rc.1", "1.0.0+build.1"
        ]

        invalid_versions = [
            "1.0", "1.0.0.0", "v1.0.0", "1.0.0-", "1.0.0+"
        ]

        for version in valid_versions:
            assert validate_semver(version), f"Version {version} should be valid"

        for version in invalid_versions:
            assert not validate_semver(version), f"Version {version} should be invalid"

        print("✅ validate_semver test passed")

    def test_is_stable_version(self):
        """Test stable version detection."""
        print("Testing is_stable_version...")

        stable_versions = ["1.0.0", "1.2.3", "2.0.0", "10.5.1"]
        prerelease_versions = [
            "1.0.0-alpha.0", "1.1.0-beta.1", "1.0.0-rc.1", "1.0.0-dev", "1.0.0-snapshot"
        ]

        for version in stable_versions:
            assert is_stable_version(version), f"Version {version} should be stable"

        for version in prerelease_versions:
            assert not is_stable_version(version), f"Version {version} should be pre-release"

        print("✅ is_stable_version test passed")

    def test_create_release_entry(self):
        """Test creating release entries."""
        print("Testing create_release_entry...")

        args = MockArgs()
        release_entry = create_release_entry(args, "1.2.3")

        expected_fields = ['version', 'released_at', 'status', 'git_branch', 'git_tag', 'commit_sha']

        for field in expected_fields:
            assert field in release_entry, f"Missing field: {field}"

        assert release_entry['version'] == "1.2.3"
        assert release_entry['git_tag'] == "v1.2.3"
        assert release_entry['git_branch'] == "release-1.2"
        assert release_entry['status'] == "stable"

        print("✅ create_release_entry test passed")

    def test_version_exists_check(self):
        """Test version existence checking."""
        print("Testing check_version_exists...")

        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            test_file = Path(f.name)

        try:
            # Test with non-existent file
            assert not check_version_exists(test_file, "1.0.0"), "Non-existent file should return False"

            # Test with file containing releases
            test_data = {
                'releases': [
                    {'version': '1.0.0', 'released_at': '2025-01-01'},
                    {'version': '0.9.0', 'released_at': '2024-12-01'}
                ]
            }
            save_yaml_file(test_file, test_data)

            # Test existing and non-existing versions
            assert check_version_exists(test_file, "1.0.0"), "Should find existing version"
            assert not check_version_exists(test_file, "2.0.0"), "Should not find non-existing version"

        finally:
            if test_file.exists():
                test_file.unlink()

        print("✅ check_version_exists test passed")

    def test_update_releases_notes(self):
        """Test updating release notes files."""
        print("Testing update_releases_notes...")

        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            test_file = f.name

        try:
            # Initial data
            initial_data = {
                'releases': [
                    {'version': '1.0.0', 'released_at': '2025-01-01', 'status': 'stable'}
                ]
            }
            save_yaml_file(test_file, initial_data)

            # New release
            args = MockArgs()
            new_release = create_release_entry(args, "1.2.3")

            # Update
            assert update_releases_notes(test_file, new_release), "Should update successfully"

            # Verify
            updated_data = load_yaml_file(test_file)
            assert len(updated_data['releases']) == 2, "Should have 2 releases"
            assert updated_data['releases'][0]['version'] == '1.2.3', "New release should be first"

            # Test duplicate version
            assert not update_releases_notes(test_file, new_release), "Should skip duplicate version"

        finally:
            if os.path.exists(test_file):
                os.unlink(test_file)

        print("✅ update_releases_notes test passed")

    def test_find_addon_directories_with_versions(self):
        """Test finding addon directories with version parsing."""
        print("Testing find_addon_directories_with_versions...")

        self.setup_test_environment()

        try:
            # Test stable versions only
            addon_info, skipped_info = find_addon_directories_with_versions(self.test_dir, include_prerelease=False)

            # Should find stable versions only
            stable_names = [info['name'] for info in addon_info]
            assert 'mysql' in stable_names, "Should find mysql (stable)"
            assert 'redis' in stable_names, "Should find redis (stable)"
            assert 'mongodb' not in stable_names, "Should not find mongodb (pre-release)"

            # Check skipped info
            assert len(skipped_info['library_charts']) == 1, "Should skip kblib"
            assert len(skipped_info['prerelease_versions']) == 2, "Should skip 2 pre-release versions"
            assert len(skipped_info['no_version']) == 1, "Should skip 1 invalid version"

            # Test including pre-release versions
            addon_info_all, skipped_info_all = find_addon_directories_with_versions(self.test_dir, include_prerelease=True)

            all_names = [info['name'] for info in addon_info_all]
            assert 'mongodb' in all_names, "Should find mongodb when including pre-release"
            assert len(skipped_info_all['prerelease_versions']) == 0, "Should not skip pre-release when included"

        finally:
            self.cleanup_test_environment()

        print("✅ find_addon_directories_with_versions test passed")

    def test_version_consistency_check(self):
        """Test version consistency checking between addon and addon-cluster."""
        print("Testing check_version_consistency...")

        addon_info_list = [
            {'name': 'mysql', 'type': 'addons', 'version': '1.0.2'},
            {'name': 'mysql', 'type': 'addons-cluster', 'version': '1.0.1'},  # Inconsistent
            {'name': 'redis', 'type': 'addons', 'version': '1.0.1'},
            {'name': 'redis', 'type': 'addons-cluster', 'version': '1.0.1'},  # Consistent
            {'name': 'mongodb', 'type': 'addons', 'version': '1.1.0'},  # No cluster pair
        ]

        inconsistencies = check_version_consistency(addon_info_list)

        assert len(inconsistencies) == 1, "Should find 1 inconsistency"
        assert inconsistencies[0]['name'] == 'mysql', "Should identify mysql as inconsistent"
        assert inconsistencies[0]['addon_version'] == '1.0.2'
        assert inconsistencies[0]['cluster_version'] == '1.0.1'

        print("✅ check_version_consistency test passed")

    def test_detailed_summary(self):
        """Test detailed summary printing."""
        print("Testing print_detailed_summary...")

        # Capture stdout
        captured_output = StringIO()

        results_summary = {
            'addons': {
                'mysql': {'status': 'UPDATED', 'version': '1.0.2'},
                'redis': {'status': 'SKIPPED (version exists)', 'version': '1.0.1'},
            },
            'addons-cluster': {
                'redis': {'status': 'UPDATED', 'version': '1.0.1'},
                'mongodb': {'status': 'FAILED (file error)', 'version': '1.1.0'},
            }
        }

        skipped_info = {
            'library_charts': [{'name': 'kblib', 'type': 'addons'}],
            'prerelease_versions': [{'name': 'postgresql', 'type': 'addons-cluster', 'version': '1.1.0-alpha.0'}],
            'no_version': []
        }

        with patch('sys.stdout', captured_output):
            print_detailed_summary(results_summary, skipped_info, 'v1.2.3', 'release-1.2')

        output = captured_output.getvalue()

        # Check that summary contains expected elements
        assert 'DETAILED SUMMARY' in output, "Should contain summary header"
        assert 'v1.2.3' in output, "Should contain git tag"
        assert 'release-1.2' in output, "Should contain git branch"
        assert 'ADDONS:' in output, "Should show addons section"
        assert 'ADDONS-CLUSTER:' in output, "Should show addons-cluster section"
        assert 'STATISTICS:' in output, "Should show statistics"
        assert 'SKIPPED DURING DISCOVERY:' in output, "Should show skipped items"
        assert 'mysql' in output and 'redis' in output, "Should list processed addons"

        print("✅ print_detailed_summary test passed")

    def test_main_function_components(self):
        """Test key components of the main function workflow."""
        print("Testing main function components...")

        self.setup_test_environment()

        try:
            # Test argument parsing
            args = MockArgs(dry_run=True, check_consistency=True)

            # Test addon discovery
            addon_info_list, skipped_info = find_addon_directories_with_versions(self.test_dir, args.include_prerelease)

            assert len(addon_info_list) > 0, "Should find some addons"
            assert len(skipped_info['library_charts']) > 0, "Should skip library charts"

            # Test release entry creation
            for addon_info in addon_info_list[:1]:  # Test with first addon
                release_entry = create_release_entry(args, addon_info['version'])
                assert 'version' in release_entry, "Should create valid release entry"
                assert release_entry['git_tag'] == args.git_tag, "Should use correct git tag"
                assert release_entry['git_branch'] == args.git_branch, "Should use correct git branch"

            # Test consistency checking
            inconsistencies = check_version_consistency(addon_info_list)
            # This should work without errors, regardless of results

            # Test summary generation (capture output)
            captured_output = StringIO()
            # Create proper results_summary structure
            results_summary = {
                'addons': {
                    'test-addon': {'status': 'DRY-RUN (would update)', 'version': '1.0.0'}
                },
                'addons-cluster': {
                    'test-cluster': {'status': 'UPDATED', 'version': '1.0.1'}
                }
            }
            with patch('sys.stdout', captured_output):
                print_detailed_summary(results_summary, skipped_info, args.git_tag, args.git_branch)

            summary_output = captured_output.getvalue()
            assert 'DETAILED SUMMARY' in summary_output, "Should generate detailed summary"
            assert args.git_tag in summary_output, "Should include git tag in summary"
            assert args.git_branch in summary_output, "Should include git branch in summary"

        finally:
            self.cleanup_test_environment()

        print("✅ main function components test passed")

    def run_all_tests(self):
        """Run all tests."""
        print("Running comprehensive tests for update_release_notes.py...\n")

        try:
            self.test_validate_semver()
            self.test_is_stable_version()
            self.test_create_release_entry()
            self.test_version_exists_check()
            self.test_update_releases_notes()
            self.test_find_addon_directories_with_versions()
            self.test_version_consistency_check()
            self.test_detailed_summary()
            self.test_main_function_components()

            print("\n🎉 ALL COMPREHENSIVE TESTS PASSED!")
            return True

        except Exception as e:
            print(f"\n❌ Test failed: {e}")
            import traceback
            traceback.print_exc()
            return False


def main():
    """Run the comprehensive test suite."""
    test_suite = TestUpdateReleaseNotes()
    success = test_suite.run_all_tests()
    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())

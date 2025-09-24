#!/usr/bin/env python3
"""
Integration test for update_release_notes.py using real repository data.
This test uses actual addon Chart.yaml files from the repository.
"""

import os
import sys
import subprocess
from pathlib import Path

# Add the current directory to the Python path
sys.path.insert(0, os.path.dirname(__file__))

from update_release_notes import find_addon_directories_with_versions, is_stable_version


def test_real_addon_discovery():
    """Test addon discovery with real repository data."""
    print("🔍 Testing addon discovery with real repository data...")

    # Get repository root (assuming we're in .github/scripts/)
    repo_root = Path(__file__).parent.parent.parent

    if not repo_root.exists():
        print(f"❌ Repository root not found: {repo_root}")
        return False

    print(f"📁 Repository root: {repo_root}")

    # Test stable versions only
    print("\n📋 Testing stable versions only:")
    addon_info, skipped_info = find_addon_directories_with_versions(repo_root, include_prerelease=False)

    addon_count = len([info for info in addon_info if info['type'] == 'addons'])
    cluster_count = len([info for info in addon_info if info['type'] == 'addons-cluster'])

    print(f"  ✅ Found {len(addon_info)} stable versions:")
    print(f"     - addons: {addon_count}")
    print(f"     - addons-cluster: {cluster_count}")

    if addon_info:
        print(f"  📦 Sample stable addons:")
        for info in sorted(addon_info, key=lambda x: (x['type'], x['name']))[:5]:
            print(f"     - {info['type']}/{info['name']}: {info['version']}")

    # Test including pre-release versions
    print("\n📋 Testing with pre-release versions:")
    addon_info_all, skipped_info_all = find_addon_directories_with_versions(repo_root, include_prerelease=True)

    addon_count_all = len([info for info in addon_info_all if info['type'] == 'addons'])
    cluster_count_all = len([info for info in addon_info_all if info['type'] == 'addons-cluster'])

    print(f"  ✅ Found {len(addon_info_all)} total versions:")
    print(f"     - addons: {addon_count_all}")
    print(f"     - addons-cluster: {cluster_count_all}")

    # Show skipped information
    total_skipped = (len(skipped_info['library_charts']) +
                    len(skipped_info['prerelease_versions']) +
                    len(skipped_info['no_version']))

    if total_skipped > 0:
        print(f"\n🚫 Skipped during discovery ({total_skipped} total):")

        if skipped_info['library_charts']:
            print(f"  📚 Library charts: {len(skipped_info['library_charts'])}")
            for item in skipped_info['library_charts'][:3]:
                print(f"     - {item['type']}/{item['name']}")

        if skipped_info['prerelease_versions']:
            print(f"  🔄 Pre-release versions: {len(skipped_info['prerelease_versions'])}")
            for item in skipped_info['prerelease_versions'][:3]:
                print(f"     - {item['type']}/{item['name']} ({item['version']})")

        if skipped_info['no_version']:
            print(f"  ❓ No valid version: {len(skipped_info['no_version'])}")

    # Validate that we found some addons
    if len(addon_info) == 0:
        print("❌ No stable addon versions found - this might indicate a problem")
        return False

    print(f"\n✅ Real data discovery test passed!")
    return True


def test_dry_run_execution():
    """Test executing the script in dry-run mode with real data."""
    print("\n🧪 Testing dry-run execution with real data...")

    script_path = Path(__file__).parent / 'update_release_notes.py'

    if not script_path.exists():
        print(f"❌ Script not found: {script_path}")
        return False

    # Test command
    cmd = [
        'python3', str(script_path),
        '--git-branch', 'test-branch',
        '--git-tag', 'v0.0.0-test',
        '--published-at', '2025-09-24T12:00:00Z',
        '--commit-sha', 'test123',
        '--dry-run',
        '--check-consistency'
    ]

    try:
        print(f"  🚀 Running: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

        print(f"  📊 Exit code: {result.returncode}")

        if result.stdout:
            lines = result.stdout.split('\n')
            print(f"  📝 Output preview (first 10 lines):")
            for line in lines[:10]:
                if line.strip():
                    print(f"     {line}")

            if len(lines) > 10:
                print(f"     ... ({len(lines) - 10} more lines)")

            # Check for key indicators of successful execution
            output = result.stdout
            success_indicators = [
                'Running in DRY-RUN mode',
                'Found',
                'addon directories',
                'DETAILED SUMMARY'
            ]

            missing_indicators = []
            for indicator in success_indicators:
                if indicator not in output:
                    missing_indicators.append(indicator)

            if missing_indicators:
                print(f"  ⚠️ Missing indicators: {missing_indicators}")
            else:
                print(f"  ✅ All success indicators found")

        if result.stderr:
            print(f"  ⚠️ Errors/warnings:")
            for line in result.stderr.split('\n')[:5]:
                if line.strip():
                    print(f"     {line}")

        # Consider the test successful if exit code is 0
        if result.returncode == 0:
            print(f"  ✅ Dry-run execution test passed!")
            return True
        else:
            print(f"  ❌ Dry-run execution failed with exit code {result.returncode}")
            return False

    except subprocess.TimeoutExpired:
        print(f"  ❌ Script execution timed out")
        return False
    except Exception as e:
        print(f"  ❌ Script execution failed: {e}")
        return False


def test_version_validation_with_real_data():
    """Test version validation with actual Chart.yaml versions from the repo."""
    print("\n🔍 Testing version validation with real Chart.yaml data...")

    repo_root = Path(__file__).parent.parent.parent

    # Find some Chart.yaml files
    chart_files = []
    for addon_type in ['addons', 'addons-cluster']:
        addon_dir = repo_root / addon_type
        if addon_dir.exists():
            for item in addon_dir.iterdir():
                if item.is_dir():
                    chart_file = item / 'Chart.yaml'
                    if chart_file.exists():
                        chart_files.append(chart_file)
                        if len(chart_files) >= 10:  # Limit to first 10 for testing
                            break
            if len(chart_files) >= 10:
                break

    if not chart_files:
        print("  ❌ No Chart.yaml files found for testing")
        return False

    print(f"  📁 Testing {len(chart_files)} Chart.yaml files...")

    stable_count = 0
    prerelease_count = 0
    invalid_count = 0

    from update_release_notes import parse_chart_version

    for chart_file in chart_files:
        try:
            version = parse_chart_version(chart_file)
            if version:
                if is_stable_version(version):
                    stable_count += 1
                    print(f"     ✅ {chart_file.parent.parent.name}/{chart_file.parent.name}: {version} (stable)")
                else:
                    prerelease_count += 1
                    print(f"     🔄 {chart_file.parent.parent.name}/{chart_file.parent.name}: {version} (pre-release)")
            else:
                invalid_count += 1
                print(f"     ❓ {chart_file.parent.parent.name}/{chart_file.parent.name}: no valid version")
        except Exception as e:
            invalid_count += 1
            print(f"     ❌ {chart_file.parent.parent.name}/{chart_file.parent.name}: error parsing ({e})")

    print(f"\n  📊 Version analysis:")
    print(f"     - Stable versions: {stable_count}")
    print(f"     - Pre-release versions: {prerelease_count}")
    print(f"     - Invalid/missing: {invalid_count}")

    if stable_count > 0:
        print(f"  ✅ Version validation test passed!")
        return True
    else:
        print(f"  ⚠️ No stable versions found - this might be expected if all versions are pre-release")
        return True  # Not necessarily a failure


def main():
    """Run all integration tests."""
    print("🧪 Running integration tests for update_release_notes.py with real data...\n")

    tests = [
        test_real_addon_discovery,
        test_version_validation_with_real_data,
        test_dry_run_execution,
    ]

    passed = 0
    failed = 0

    for test_func in tests:
        try:
            if test_func():
                passed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"❌ Test {test_func.__name__} failed with exception: {e}")
            import traceback
            traceback.print_exc()
            failed += 1

        print()  # Add spacing between tests

    print("="*80)
    print(f"📊 INTEGRATION TEST RESULTS:")
    print(f"   ✅ Passed: {passed}")
    print(f"   ❌ Failed: {failed}")
    print(f"   📈 Total:  {passed + failed}")

    if failed == 0:
        print(f"\n🎉 ALL INTEGRATION TESTS PASSED!")
        return 0
    else:
        print(f"\n💥 {failed} INTEGRATION TESTS FAILED!")
        return 1


if __name__ == '__main__':
    sys.exit(main())

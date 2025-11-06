#!/usr/bin/env python3
"""
Test runner for update_release_notes.py test suites.
Executes both unit tests and integration tests.
"""

import sys
import os
from pathlib import Path

def run_test_suite(test_file, description):
    """Run a test suite and return success status."""
    print(f"\n{'='*80}")
    print(f"🧪 RUNNING {description}")
    print(f"{'='*80}")

    try:
        # Import and run the test
        test_path = Path(__file__).parent / test_file
        if not test_path.exists():
            print(f"❌ Test file not found: {test_path}")
            return False

        # Execute the test file
        import subprocess
        result = subprocess.run([sys.executable, str(test_path)],
                              capture_output=False, text=True)

        return result.returncode == 0

    except Exception as e:
        print(f"❌ Failed to run {test_file}: {e}")
        return False


def main():
    """Run all test suites for update_release_notes.py."""
    print("🚀 RUNNING ALL TESTS FOR update_release_notes.py")
    print(f"Python: {sys.executable}")
    print(f"Working directory: {os.getcwd()}")

    test_suites = [
        ("test_comprehensive_release_notes.py", "COMPREHENSIVE UNIT TESTS"),
        ("test_integration_real_data.py", "INTEGRATION TESTS WITH REAL DATA"),
    ]

    results = []

    for test_file, description in test_suites:
        success = run_test_suite(test_file, description)
        results.append((description, success))

    # Summary
    print(f"\n{'='*80}")
    print(f"📊 FINAL TEST RESULTS")
    print(f"{'='*80}")

    passed = sum(1 for _, success in results if success)
    total = len(results)

    for description, success in results:
        status = "✅ PASSED" if success else "❌ FAILED"
        print(f"  {status}: {description}")

    print(f"\n📈 SUMMARY: {passed}/{total} test suites passed")

    if passed == total:
        print(f"\n🎉 ALL TEST SUITES PASSED!")
        return 0
    else:
        print(f"\n💥 {total - passed} TEST SUITES FAILED!")
        return 1


if __name__ == '__main__':
    sys.exit(main())

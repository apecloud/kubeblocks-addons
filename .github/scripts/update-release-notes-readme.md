# Readme for Update Release Notes

This directory contains scripts for automatically updating addon release notes when new releases are published.

## Files

### `update_release_notes.py`
The main script that updates `releases_notes.yaml` files across all addon and addon-cluster directories using individual Chart.yaml version.

**Features:**
- Updates both `addons/` and `addons-cluster/` directories
- **Per-addon versioning**: Parses version from each addon's `Chart.yaml` file
- **Stable version filtering**: Only processes stable versions by default, skips pre-release versions (alpha, beta, rc, dev, etc.)
- **Smart version checking**: Skips addons where the version already exists in release notes
- **Library chart exclusion**: Automatically skips `kblib` and other library charts
- **Detailed summary report**: Shows complete status for all addons and addon-clusters with statistics
- **Supports dry-run**: Run without making actual changes to files with `--dry-run` flag
- **Optional Prerelease version**: Include pre-release versions (alpha, beta, rc, dev, etc.) with `--include-prerelease` flag

**Usage:**

Install dependencies:
```bash
pip install pyyaml
```

Run the script:
```bash
python update_release_notes.py \
  --git-branch "release-1.0" \
  --git-tag "v1.2.3" \
  --published-at "2025-09-24T12:00:00Z" \
  --commit-sha "abc123" \
  [--dry-run] \
  [--include-prerelease] \
  [--check-consistency]
```

**Options:**
- `--include-prerelease`: Include pre-release versions (alpha, beta, rc, dev, etc.) - by default only stable versions are processed
- `--check-consistency`: Check version consistency between addon and addon-cluster pairs with the same name
- `--dry-run`: Run without making actual changes to files

### `test_comprehensive_release_notes.py`
Comprehensive unit test suite that covers all functionality of `update_release_notes.py`.

**Features:**
- Complete function coverage with unit tests
- Mock environment creation for isolated testing
- Edge case and error condition testing
- Detailed validation of all features

### `test_integration_real_data.py`
Integration test suite that validates the script with real repository data.

**Features:**
- Tests with actual Chart.yaml files from the repository
- End-to-end workflow validation
- Real data discovery and processing
- Performance and timeout testing

### `run_tests.py`
Test runner that executes both unit and integration test suites.

**Usage:**
```bash
# Run all tests
python run_tests.py

# Or run individual test suites
python test_comprehensive_release_notes.py
python test_integration_real_data.py
```

## Release Notes Format

The script maintains YAML files with the following structure:

```yaml
releases:
  - version: "1.0.1" # addon or addon-cluster version
    released_at: "2025-09-24" # release date
    status: "stable"
    git_branch: "release-1.0" # git branch name
    git_tag: "v1.2.3"  # git tag naem
    commit_sha: "abc123def456" # commit sha , this is optional
```

## Testing

The script includes comprehensive test coverage with both unit and integration tests:

### Running Tests

**Quick Test (All Suites):**
```bash
python .github/scripts/run_tests.py
```

**Individual Test Suites:**
```bash
# Unit tests with mock data
python .github/scripts/test_comprehensive_release_notes.py

# Integration tests with real repository data
python .github/scripts/test_integration_real_data.py
```

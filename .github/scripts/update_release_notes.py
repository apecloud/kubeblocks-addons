#!/usr/bin/env python3
"""
Script to update release_notes.yaml files in addon chart folders.
This script is triggered by GitHub releases and adds new release information
to each addon's releases_notes.yaml file.
"""

import argparse
import os
import sys
import yaml
import re
from datetime import datetime
from pathlib import Path


def load_yaml_file(file_path):
    """Load YAML file and return its content."""
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            return yaml.safe_load(file) or {}
    except FileNotFoundError:
        return {}
    except yaml.YAMLError as e:
        print(f"Error parsing YAML file {file_path}: {e}")
        return {}


def save_yaml_file(file_path, data):
    """Save data to YAML file with proper formatting."""
    try:
        with open(file_path, 'w', encoding='utf-8') as file:
            yaml.dump(data, file, default_flow_style=False,
                     allow_unicode=True, sort_keys=False, indent=2)
        return True
    except Exception as e:
        print(f"Error saving YAML file {file_path}: {e}")
        return False


def parse_release_date(published_at):
    """Parse GitHub release published_at timestamp to YYYY-MM-DD format."""
    try:
        # Parse ISO 8601 format: 2025-09-11T12:34:56Z
        dt = datetime.fromisoformat(published_at.replace('Z', '+00:00'))
        return dt.strftime('%Y-%m-%d')
    except Exception:
        # Fallback to current date if parsing fails
        return datetime.now().strftime('%Y-%m-%d')

def create_release_entry(args, addon_version):
    """Create a new release entry from command line arguments."""
    # Use addon's Chart.yaml version
    version = addon_version
    release_date = parse_release_date(args.published_at) if args.published_at else datetime.now().strftime('%Y-%m-%d')
    status = "stable"

    return {
        'version': version,
        'released_at': release_date,
        'status': status,
        'git_branch': args.git_branch,
        'git_tag': args.git_tag,
        'commit_sha': args.commit_sha if args.commit_sha else "",
    }

def check_version_exists(file_path, version):
    """Check if a version already exists in the releases_notes.yaml file."""
    if not file_path.exists():
        return False

    try:
        data = load_yaml_file(file_path)
        if 'releases' not in data or not data['releases']:
            return False

        existing_versions = [release.get('version') for release in data['releases'] if release.get('version')]
        return version in existing_versions
    except Exception as e:
        print(f"WARNING: Failed to check existing versions in {file_path}: {e}")
        return False


def update_releases_notes(file_path, new_release):
    """Update releases_notes.yaml file with new release information."""
    # Load existing data
    data = load_yaml_file(file_path)

    # Ensure releases key exists
    if 'releases' not in data:
        data['releases'] = []

    # Check if version already exists
    existing_versions = [release.get('version') for release in data['releases']]
    if new_release['version'] in existing_versions:
        print(f"Version {new_release['version']} already exists in {file_path}, skipping...")
        return False

    # Add new release to the beginning of the list (most recent first)
    data['releases'].insert(0, new_release)

    # Save updated data
    return save_yaml_file(file_path, data)


def validate_semver(version):
    """Validate if version follows semantic versioning (with optional pre-release suffixes)."""
    # Pattern for semantic versioning with optional pre-release (alpha, beta, rc) and build metadata
    semver_pattern = r'^(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z0-9\-\.]+))?(?:\+([a-zA-Z0-9\-\.]+))?$'
    return re.match(semver_pattern, version) is not None


def is_stable_version(version):
    """Check if a version is stable (not a pre-release version)."""
    if not version:
        return False

    # Pre-release indicators
    prerelease_keywords = ['alpha', 'beta', 'rc', 'dev', 'snapshot', 'pre']

    version_lower = version.lower()

    # Check if version contains any pre-release keywords
    for keyword in prerelease_keywords:
        if keyword in version_lower:
            return False

    # Check for pre-release pattern (version-something)
    if '-' in version:
        # Split on dash and check the pre-release part
        parts = version.split('-', 1)
        if len(parts) > 1:
            prerelease_part = parts[1].lower()
            # If it's just numbers or build metadata, it might still be stable
            # But if it contains known pre-release keywords, it's not stable
            for keyword in prerelease_keywords:
                if keyword in prerelease_part:
                    return False

    return True


def parse_chart_version(chart_file_path):
    """Parse version from Chart.yaml file."""
    try:
        chart_data = load_yaml_file(chart_file_path)
        version = chart_data.get('version')
        if not version:
            print(f"WARNING: No version found in {chart_file_path}")
            return None

        version_str = str(version).strip()

        # Validate version format
        if not validate_semver(version_str):
            print(f"WARNING: Version '{version_str}' in {chart_file_path} is not valid semver")
            # Still return it, but with warning

        return version_str
    except Exception as e:
        print(f"ERROR: Failed to parse Chart.yaml at {chart_file_path}: {e}")
        return None


def find_addon_directories_with_versions(base_path, include_prerelease=False):
    """Find all addon directories that contain Chart.yaml files and extract their versions."""
    addon_info = []
    skipped_info = {
        'library_charts': [],
        'prerelease_versions': [],
        'no_version': []
    }

    # Charts to skip (library charts or internal dependencies)
    skip_charts = {'kblib'}

    # Check both 'addons' and 'addons-cluster' directories
    for addon_type in ['addons', 'addons-cluster']:
        addons_path = Path(base_path) / addon_type

        if not addons_path.exists():
            print(f"Addons directory not found: {addons_path}")
            continue

        for item in addons_path.iterdir():
            if item.is_dir():
                # Skip library charts and internal dependencies
                if item.name in skip_charts:
                    print(f"SKIPPED: {addon_type}/{item.name} (library chart)")
                    skipped_info['library_charts'].append({
                        'name': item.name,
                        'type': addon_type,
                        'reason': 'library chart'
                    })
                    continue

                chart_file = item / 'Chart.yaml'
                if chart_file.exists():
                    version = parse_chart_version(chart_file)
                    if version:
                        # Check if version is stable (not pre-release) unless explicitly including pre-releases
                        if include_prerelease or is_stable_version(version):
                            addon_info.append({
                                'path': item,
                                'name': item.name,
                                'type': addon_type,
                                'version': version,
                                'chart_file': chart_file
                            })
                        else:
                            print(f"SKIPPED: {addon_type}/{item.name} (pre-release version: {version})")
                            skipped_info['prerelease_versions'].append({
                                'name': item.name,
                                'type': addon_type,
                                'version': version,
                                'reason': 'pre-release version'
                            })
                    else:
                        print(f"WARNING: Skipping {addon_type}/{item.name} - no valid version found")
                        skipped_info['no_version'].append({
                            'name': item.name,
                            'type': addon_type,
                            'reason': 'no valid version'
                        })

    return addon_info, skipped_info


def find_addon_directories(base_path):
    """Find all addon directories that contain Chart.yaml files (legacy function for compatibility)."""
    addon_info, _ = find_addon_directories_with_versions(base_path)
    return [info['path'] for info in addon_info]


def check_version_consistency(addon_info_list):
    """Check version consistency between addon and addon-cluster pairs."""
    addon_versions = {}
    addon_cluster_versions = {}

    # Group by name and type
    for info in addon_info_list:
        if info['type'] == 'addons':
            addon_versions[info['name']] = info['version']
        elif info['type'] == 'addons-cluster':
            addon_cluster_versions[info['name']] = info['version']

    # Find pairs and check consistency
    inconsistent_pairs = []
    for name in addon_versions:
        if name in addon_cluster_versions:
            addon_ver = addon_versions[name]
            cluster_ver = addon_cluster_versions[name]
            if addon_ver != cluster_ver:
                inconsistent_pairs.append({
                    'name': name,
                    'addon_version': addon_ver,
                    'cluster_version': cluster_ver
                })

    if inconsistent_pairs:
        print("\n⚠️  Version inconsistencies found between addon and addon-cluster:")
        for pair in inconsistent_pairs:
            print(f"  - {pair['name']}: addons/{pair['addon_version']} vs addons-cluster/{pair['cluster_version']}")

    return inconsistent_pairs


def print_detailed_summary(results_summary, skipped_info, git_tag, git_branch):
    """Print a detailed summary of all addon processing results."""
    print("\n" + "="*80)
    print(f"📋 DETAILED SUMMARY - Release {git_tag} on {git_branch}")
    print("="*80)

    # Status icons
    status_icons = {
        'UPDATED': '✅',
        'SKIPPED (version exists)': '⏭️',
        'SKIPPED (no changes)': '⏭️',
        'DRY-RUN (would update)': '🔄',
        'FAILED': '❌'
    }

    for addon_type in ['addons', 'addons-cluster']:
        if not results_summary[addon_type]:
            continue

        print(f"\n📦 {addon_type.upper()}:")
        print("-" * 60)

        # Sort by addon name for consistent output
        sorted_addons = sorted(results_summary[addon_type].items())

        for addon_name, result in sorted_addons:
            status = result['status']
            version = result['version']

            # Get icon based on status
            icon = status_icons.get(status.split('(')[0].strip(), '❓')
            if status.startswith('FAILED'):
                icon = '❌'

            # Format status for display
            display_status = status
            if len(status) > 35:
                display_status = status[:32] + "..."

            print(f"  {icon} {addon_name:<25} {version:<15} {display_status}")

    # Summary statistics
    print(f"\n📊 STATISTICS:")
    print("-" * 60)

    all_results = {}
    for addon_type in results_summary:
        for addon_name, result in results_summary[addon_type].items():
            status_key = result['status'].split('(')[0].strip()
            if status_key.startswith('FAILED'):
                status_key = 'FAILED'
            all_results[status_key] = all_results.get(status_key, 0) + 1

    total = sum(all_results.values())
    for status, count in sorted(all_results.items()):
        percentage = (count / total * 100) if total > 0 else 0
        icon = status_icons.get(status, '❓')
        print(f"  {icon} {status:<25} {count:>3} ({percentage:>5.1f}%)")

    print(f"\n  📈 TOTAL PROCESSED: {total}")

    # Show skipped items (not processed)
    total_skipped_discovery = (len(skipped_info['library_charts']) +
                              len(skipped_info['prerelease_versions']) +
                              len(skipped_info['no_version']))

    if total_skipped_discovery > 0:
        print(f"\n🚫 SKIPPED DURING DISCOVERY:")
        print("-" * 60)

        if skipped_info['library_charts']:
            print(f"  📚 Library Charts ({len(skipped_info['library_charts'])}):")
            for item in sorted(skipped_info['library_charts'], key=lambda x: (x['type'], x['name'])):
                print(f"    - {item['type']}/{item['name']}")

        if skipped_info['prerelease_versions']:
            print(f"  🔄 Pre-release Versions ({len(skipped_info['prerelease_versions'])}):")
            for item in sorted(skipped_info['prerelease_versions'], key=lambda x: (x['type'], x['name'])):
                print(f"    - {item['type']}/{item['name']} ({item['version']})")

        if skipped_info['no_version']:
            print(f"  ❓ No Valid Version ({len(skipped_info['no_version'])}):")
            for item in sorted(skipped_info['no_version'], key=lambda x: (x['type'], x['name'])):
                print(f"    - {item['type']}/{item['name']}")

        print(f"\n  🚫 TOTAL SKIPPED: {total_skipped_discovery}")

    print("="*80)


def main():
    parser = argparse.ArgumentParser(description='Update release notes for addon charts')
    parser.add_argument('--git-branch', required=True, help='Git branch for the release')
    parser.add_argument('--git-tag', required=True, help='Git tag for the release')
    parser.add_argument('--published-at', required=False, help='Release published timestamp')
    parser.add_argument('--commit-sha', required=False, help='Commit SHA')
    parser.add_argument('--dry-run', action='store_true', help='Run in dry-run mode without making changes')
    parser.add_argument('--include-prerelease', action='store_true', help='Include pre-release versions (alpha, beta, rc, etc.)')
    parser.add_argument('--check-consistency', action='store_true', help='Check version consistency between addon and addon-cluster pairs')

    args = parser.parse_args()

    print(f"Processing release: {args.git_tag} on branch {args.git_branch}")
    if args.dry_run:
        print("Running in DRY-RUN mode - no files will be modified")

    # Validate inputs
    if not args.git_tag.strip():
        print("ERROR: git-tag cannot be empty")
        sys.exit(1)

    if not args.git_branch.strip():
        print("ERROR: git-branch cannot be empty")
        sys.exit(1)

    # Get the repository root (assuming script is in .github/scripts/)
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent.parent

    if not repo_root.exists():
        print(f"ERROR: Repository root not found: {repo_root}")
        sys.exit(1)

    # Find all addon directories with their versions
    addon_info_list, skipped_info = find_addon_directories_with_versions(repo_root, args.include_prerelease)

    if not addon_info_list:
        if args.include_prerelease:
            print("ERROR: No addon directories found")
        else:
            print("ERROR: No stable addon versions found. Use --include-prerelease to include pre-release versions.")
        sys.exit(1)

    # Separate counts by directory type
    addon_count = len([info for info in addon_info_list if info['type'] == 'addons'])
    addon_cluster_count = len([info for info in addon_info_list if info['type'] == 'addons-cluster'])

    if args.include_prerelease:
        print(f"Found {len(addon_info_list)} addon directories (including pre-release versions):")
    else:
        print(f"Found {len(addon_info_list)} addon directories (stable versions only):")
    print(f"  - addons: {addon_count}")
    print(f"  - addons-cluster: {addon_cluster_count}")

    # Check version consistency between addon and addon-cluster pairs if requested
    inconsistencies = []
    if args.check_consistency:
        inconsistencies = check_version_consistency(addon_info_list)

    updated_count = 0
    failed_count = 0
    skipped_count = 0

    # Track results for summary
    results_summary = {
        'addons': {},
        'addons-cluster': {}
    }

    # Update each addon's releases_notes.yaml
    for addon_info in addon_info_list:
        addon_dir = addon_info['path']
        addon_name = addon_info['name']
        addon_type = addon_info['type']
        addon_version = addon_info['version']
        releases_notes_file = addon_dir / 'releases_notes.yaml'

        print(f"Processing {addon_type}/{addon_name} (Chart version: {addon_version})...")

        try:
            # Check if version already exists to avoid unnecessary processing
            if releases_notes_file.exists() and check_version_exists(releases_notes_file, addon_version):
                print(f"SKIPPED: Version {addon_version} already exists for {addon_type}/{addon_name}")
                skipped_count += 1
                results_summary[addon_type][addon_name] = {
                    'status': 'SKIPPED (version exists)',
                    'version': addon_version
                }
                continue

            # Create new release entry using the addon's Chart.yaml version
            new_release = create_release_entry(args, addon_version)

            # Create the file if it doesn't exist
            if not releases_notes_file.exists():
                print(f"Creating new releases_notes.yaml for {addon_type}/{addon_name}")
                if not args.dry_run:
                    initial_data = {'releases': []}
                    if not save_yaml_file(releases_notes_file, initial_data):
                        print(f"ERROR: Failed to create initial file for {addon_type}/{addon_name}")
                        failed_count += 1
                        results_summary[addon_type][addon_name] = {
                            'status': 'FAILED (file creation)',
                            'version': addon_version
                        }
                        continue

            # Update the file
            if args.dry_run:
                print(f"DRY-RUN: Would update releases_notes.yaml for {addon_type}/{addon_name} with version {addon_version}")
                updated_count += 1
                results_summary[addon_type][addon_name] = {
                    'status': 'DRY-RUN (would update)',
                    'version': addon_version
                }
            else:
                if update_releases_notes(releases_notes_file, new_release):
                    print(f"✅ Updated releases_notes.yaml for {addon_type}/{addon_name} with version {addon_version}")
                    updated_count += 1
                    results_summary[addon_type][addon_name] = {
                        'status': 'UPDATED',
                        'version': addon_version
                    }
                else:
                    print(f"No changes needed for {addon_type}/{addon_name} (version {addon_version} already exists)")
                    results_summary[addon_type][addon_name] = {
                        'status': 'SKIPPED (no changes)',
                        'version': addon_version
                    }
        except Exception as e:
            print(f"ERROR: Failed to process {addon_type}/{addon_name}: {e}")
            failed_count += 1
            results_summary[addon_type][addon_name] = {
                'status': f'FAILED ({str(e)[:50]}...)',
                'version': addon_version
            }

    print(f"Summary: {updated_count} updated, {skipped_count} skipped, {failed_count} failed")

    # Print detailed summary
    print_detailed_summary(results_summary, skipped_info, args.git_tag, args.git_branch)

    if failed_count > 0:
        print(f"\n❌ ERROR: {failed_count} addons failed to update")
        sys.exit(1)

    if updated_count == 0:
        if skipped_count > 0:
            print("\n✅ No files were updated (all versions already exist)")
        else:
            print("\n✅ No files were updated")
        sys.exit(0)

    print(f"\n✅ Successfully processed {len(addon_info_list)} addons!")


if __name__ == '__main__':
    main()

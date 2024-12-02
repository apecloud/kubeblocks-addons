
# Enable An Add-on

If the Addon you need is not enabled, you can enable it by following the steps below.

## Using Helm

```bash
# Add Helm repo
helm repo add kubeblocks-addons https://apecloud.github.io/helm-charts
# If github is not accessible or very slow for you, please use following repo instead
helm repo add kubeblocks-addons https://jihulab.com/api/v4/projects/150246/packages/helm/stable
# Update helm repo
helm repo update
# Search versions of the Addon
helm search repo kubeblocks/{addonName} --versions
# Install the version you want (replace $version with the one you need)
helm upgrade -i mysql kubeblocks-addons/{addonName} --version $version -n kb-system
```

## Using kbcli

Before installing addons, make sure you have an addon index added.
If not, please add one:

```bash
# add an index, kubeblocks is added by default
kbcli addon index add kubeblocks https://github.com/apecloud/block-index.git
# update the index
kbcli addon index update kubeblocks
# update all index
kbcli addon index update --all
```

To search annd install an addon:

```bash
# Search Addon
kbcli addon search {addonName}
# Install Addon with the version you want, replace $version with the one you need
kbcli addon install {addonName} --version $version
# To upgrade the addon, you can use the following command
kbcli addon upgrade {addonName} --version $version
```

To enable or disable an addon:

```bash
# Enable Addon
kbcli addon enable {addonName}
# Disable Addon
kbcli addon disable {addonName}
```

To check addon status:

```bash
kbcli addon describe {addonName}
```

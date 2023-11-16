#!/usr/bin/env python3
# -*- coding:utf-8 -*-
# generate addon CR based on helm chart

import copy
import os
import sys

import yaml

names = sys.argv[1:]
helmRepoURL = 'https://jihulab.com/api/v4/projects/150246/packages/helm/stable/charts/'

kbVersionKey = 'addon.kubeblocks.io/kubeblocks-version'
defaultIsEmptyKey = 'addons.extensions.kubeblocks.io/default-is-empty'
appNameKey = 'app.kubernetes.io/name'
appVersionKey = 'app.kubernetes.io/version'

if len(names) == 0:
    print("Usage: python3 gen-addon-crs.py <addon1> <addon2> ...")

if len(names) == 1 and names[0] == 'all':
    names = os.listdir('addons')
    # if name end with _cluster, or name is kblib, common, skip
    names = [name for name in names if not name.endswith('-cluster') and name not in ['kblib', 'common' 'neonvm']]

for name in names:
    path = os.path.join('addons', name)
    if not os.path.isdir(path):
        continue
    chart_file = os.path.join(path, "Chart.yaml")
    if not os.path.isfile(chart_file):
        continue
    # read Chart.yaml and build addon CR
    with open(chart_file, 'r') as f:
        print("Generating addon CR for " + name)
        chart = yaml.safe_load(f)
        if 'annotations' not in chart:
            print("Skip generating addon CR for " + name)
            continue
        version = chart['version']
        name = chart['name']
        addonName = name + "-" + version
        annotations = chart['annotations']

        # build labels
        labels = copy.deepcopy(annotations)
        if kbVersionKey not in labels:
            print("Skip generating addon CR for " + name)
            continue
        del labels[kbVersionKey]
        labels[appVersionKey] = version
        labels[appNameKey] = name

        cr = {
            'apiVersion': 'extensions.kubeblocks.io/v1alpha1',
            'kind': 'Addon',
            'metadata': {
                'name': name,
                'labels': labels,
                'annotations': {
                    kbVersionKey: annotations[kbVersionKey],
                    defaultIsEmptyKey: "true",
                },
            },
            'spec': {
                'description': chart['description'],
                'type': 'Helm',
                'helm': {
                    'chartLocationURL': helmRepoURL + addonName + '.tgz'
                },
                'defaultInstallValues': [
                    {
                        'enabled': True
                    }
                ],
                'installable': {
                    'autoInstall': True
                }
            },
        }

        # output to a temp dir, if temp do not exist, create it
        outputDir = os.path.join('temp', name)
        if not os.path.isdir(outputDir):
            os.makedirs(outputDir)
        addonCR = os.path.join(outputDir, version + ".yaml")
        with open(addonCR, 'w') as f:
            yaml.safe_dump(cr, f)

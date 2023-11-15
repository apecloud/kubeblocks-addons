#!/usr/bin/env python3
# -*- coding:utf-8 -*-
# generate addon CR based on helm chart

import copy
import os
import sys

import yaml

names = sys.argv[1:]
helmRepoURL = 'https://jihulab.com/api/v4/projects/85949/packages/helm/stable/charts/'
kbVersionKey = 'addon.kubeblocks.io/kubeblocks-version'

if len(names) == 0:
    print("Usage: python3 gen-addon-crs.py <addon1> <addon2> ...")

if len(names) == 1 and names[0] == 'all':
    names = os.listdir('addons')
    # if name end with _cluster, or name is kblib, common, skip
    names = [name for name in names if not name.endswith('_cluster') and name not in ['kblib', 'common' 'neonvm']]

for name in names:
    path = os.path.join('addons', name)
    if not os.path.isdir(path):
        continue
    chart_file = os.path.join(path, "Chart.yaml")
    if not os.path.isfile(chart_file):
        continue
    # read Chart.yaml and build addon CR
    with open(chart_file, 'r') as f:
        chart = yaml.safe_load(f)
        version = chart['version']
        name = chart['name']
        addonName = name + "-" + version
        annotations = chart['annotations']

        # build labels
        labels = copy.deepcopy(annotations)
        del labels[kbVersionKey]
        labels['app.kubernetes.io/version'] = version

        cr = {
            'apiVersion': 'extensions.kubeblocks.io/v1alpha1',
            'kind': 'Addon',
            'metadata': {
                'name': addonName,
                'labels': labels,
                'annotations': {
                    kbVersionKey: annotations[kbVersionKey]
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
        if not os.path.isdir('temp'):
            os.mkdir('temp')
        addonCR = os.path.join('temp', addonName + ".yaml")
        with open(addonCR, 'w') as f:
            yaml.safe_dump(cr, f)

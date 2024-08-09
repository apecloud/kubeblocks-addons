# What is ShellSpec

ShellSpec is a full-featured BDD unit testing framework for all kinds of shells.

details refer: https://github.com/shellspec/shellspec

# How to run the test cases in KubeBlocks Addons

## run with make scripts-test command

run the `make scripts-test` command in the root directory of the KubeBlocks Addons repository.

an example of the output:

```bash
➜  kubeblocks-addons git:(main) ✗ make scripts-test
ShellSpec is detected: /opt/homebrew/bin/shellspec
..............F...................

Examples:
  1) kubeblocks pods library tests min_lexicographical_order_pod with setting KB_POD_LIST env variable min_lexicographical_order_pod should return pod-1
     When call min_lexicographical_order_pod pod-pod-0,pod-1,pod-pod-1

     1.1) The output should eq pod-0

            expected: "pod-0"
                 got: "pod-1"

          # addons/kblib/scripts-ut-spec/libpods_spec.sh:91

Finished in 0.53 seconds (user 0.62 seconds, sys 0.13 seconds)
34 examples, 1 failure


Failure examples / Errors: (Listed here affect your suite's status)

shellspec addons/kblib/scripts-ut-spec/libpods_spec.sh:89 # 1) kubeblocks pods library tests min_lexicographical_order_pod with setting KB_POD_LIST env variable min_lexicographical_order_pod should return pod-1 FAILED

make: *** [scripts-test] Error 101
```

## run with shellspec command

You can also run specified unit test cases by executing the `shellspec` command in the root directory of the KubeBlocks Addons repository.

First, you need to install shellspec. For installation instructions, please refer: [shellspec installation](https://github.com/shellspec/shellspec?tab=readme-ov-file#installation) 

an example of the output:

```bash
➜  kubeblocks-addons git:(main) ✗ /opt/homebrew/bin/shellspec --load-path ./shellspec addons/kblib/scripts-ut-spec/libpods_spec.sh
Running: /bin/sh [bash 3.2.57(1)-release]
.........F

Examples:
  1) kubeblocks pods library tests min_lexicographical_order_pod with setting KB_POD_LIST env variable min_lexicographical_order_pod should return pod-1
     When call min_lexicographical_order_pod pod-pod-0,pod-1,pod-pod-1

     1.1) The output should eq pod-0

            expected: "pod-0"
                 got: "pod-1"

          # addons/kblib/scripts-ut-spec/libpods_spec.sh:91

Finished in 0.28 seconds (user 0.26 seconds, sys 0.05 seconds)
10 examples, 1 failure


Failure examples / Errors: (Listed here affect your suite's status)

shellspec addons/kblib/scripts-ut-spec/libpods_spec.sh:89 # 1) kubeblocks pods library tests min_lexicographical_order_pod with setting KB_POD_LIST env variable min_lexicographical_order_pod should return pod-1 FAILED
```

# Start to write unit test cases for KubeBlocks Addons

## create a dedicated directory for the test cases

by default, the `make scripts-test` command will run the test cases under the `scripts-ut-spec` directory in all the addons,

so we need to create a dedicated directory for the test cases. for example

```bash
mkdir -p addons/redis/scripts-ut-spec
```

## write the test cases with shellspec DSL

ShellSpec has its own DSL to write tests. For the details of the DSL, please refer: [ShellSpec DSL](https://github.com/shellspec/shellspec?tab=readme-ov-file#dsl-syntax)

the test cases files should be named with the suffix `_spec.sh` and placed under the `scripts-ut-spec` directory.

some common spec examples can be found here: [ShellSpec Examples](https://github.com/shellspec/shellspec/tree/master/examples/spec)




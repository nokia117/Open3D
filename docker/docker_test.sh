#!/usr/bin/env bash
#
# docker_test.sh is used to test Open3D docker images built by docker_build.sh
#
# Guidelines:
# - Use a flat list of options. No additional arguments.
#   The option names should match exactly the ones used in docker_build.sh.
# - No external environment variables.
#   - This script should not make assumptions on external environment variables.
#   - Environment variables are imported from docker_build.sh.

set -euo pipefail

__usage_docker_test="USAGE:
    $(basename $0) [OPTION]

OPTION:
    # OpenBLAS AMD64 (Dockerfile.openblas)
    openblas-amd64-py36-dev     : OpenBLAS AMD64 3.6 wheel, developer mode
    openblas-amd64-py37-dev     : OpenBLAS AMD64 3.7 wheel, developer mode
    openblas-amd64-py38-dev     : OpenBLAS AMD64 3.8 wheel, developer mode
    openblas-amd64-py39-dev     : OpenBLAS AMD64 3.9 wheel, developer mode
    openblas-amd64-py36         : OpenBLAS AMD64 3.6 wheel, release mode
    openblas-amd64-py37         : OpenBLAS AMD64 3.7 wheel, release mode
    openblas-amd64-py38         : OpenBLAS AMD64 3.8 wheel, release mode
    openblas-amd64-py39         : OpenBLAS AMD64 3.9 wheel, release mode

    # OpenBLAS ARM64 (Dockerfile.openblas)
    openblas-arm64-py36-dev     : OpenBLAS ARM64 3.6 wheel, developer mode
    openblas-arm64-py37-dev     : OpenBLAS ARM64 3.7 wheel, developer mode
    openblas-arm64-py38-dev     : OpenBLAS ARM64 3.8 wheel, developer mode
    openblas-arm64-py39-dev     : OpenBLAS ARM64 3.9 wheel, developer mode
    openblas-arm64-py36         : OpenBLAS ARM64 3.6 wheel, release mode
    openblas-arm64-py37         : OpenBLAS ARM64 3.7 wheel, release mode
    openblas-arm64-py38         : OpenBLAS ARM64 3.8 wheel, release mode
    openblas-arm64-py39         : OpenBLAS ARM64 3.9 wheel, release mode

    # Ubuntu CPU CI (Dockerfile.ci)
    cpu-static                  : Ubuntu CPU static
    cpu-shared                  : Ubuntu CPU shared
    cpu-shared-release          : Ubuntu CPU shared, release mode
    cpu-shared-ml               : Ubuntu CPU shared with ML
    cpu-shared-ml-release       : Ubuntu CPU shared with ML, release mode

    # Sycl CPU CI (Dockerfile.ci)
    sycl-shared                : SYCL (oneAPI) with shared lib
    sycl-static                : SYCL (oneAPI) with static lib

    # ML CIs (Dockerfile.ci)
    2-bionic                   : CUDA CI, 2-bionic, developer mode
    3-ml-shared-bionic-release : CUDA CI, 3-ml-shared-bionic, release mode
    3-ml-shared-bionic         : CUDA CI, 3-ml-shared-bionic, developer mode
    4-shared-bionic            : CUDA CI, 4-shared-bionic, developer mode
    4-shared-bionic-release    : CUDA CI, 4-shared-bionic, release mode
    5-ml-focal                 : CUDA CI, 5-ml-focal, developer mode
"

HOST_OPEN3D_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. >/dev/null 2>&1 && pwd)"

print_usage_and_exit_docker_test() {
    echo "$__usage_docker_test"
    exit 1
}

ci_print_env() {
    echo "[ci_print_env()] DOCKER_TAG=${DOCKER_TAG}"
    echo "[ci_print_env()] BASE_IMAGE=${BASE_IMAGE}"
    echo "[ci_print_env()] DEVELOPER_BUILD=${DEVELOPER_BUILD}"
    echo "[ci_print_env()] CCACHE_TAR_NAME=${CCACHE_TAR_NAME}"
    echo "[ci_print_env()] CMAKE_VERSION=${CMAKE_VERSION}"
    echo "[ci_print_env()] CCACHE_VERSION=${CCACHE_VERSION}"
    echo "[ci_print_env()] PYTHON_VERSION=${PYTHON_VERSION}"
    echo "[ci_print_env()] BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}"
    echo "[ci_print_env()] BUILD_CUDA_MODULE=${BUILD_CUDA_MODULE}"
    echo "[ci_print_env()] BUILD_TENSORFLOW_OPS=${BUILD_TENSORFLOW_OPS}"
    echo "[ci_print_env()] BUILD_PYTORCH_OPS=${BUILD_PYTORCH_OPS}"
    echo "[ci_print_env()] PACKAGE=${PACKAGE}"
}

restart_docker_daemon_if_on_gcloud() {
    # Sometimes `docker run` may fail on the second run on Google Cloud with the
    # following error:
    # ```
    # docker: Error response from daemon: OCI runtime create failed:
    # container_linux.go:349: starting container process caused
    # "process_linux.go:449: container init caused \"process_linux.go:432:
    # running prestart hook 0 caused \\\"error running hook: exit status 1,
    # stdout: , stderr: nvidia-container-cli: initialization error:
    # nvml error: driver/library version mismatch\\\\n\\\"\"": unknown.
    # ```
    if curl metadata.google.internal -i | grep Google; then
        # https://stackoverflow.com/a/30921162/1255535
        echo "[restart_docker_daemon_if_on_gcloud()] Restarting Docker daemon on Google Cloud."
        sudo systemctl daemon-reload
        sudo systemctl restart docker
    else
        echo "[restart_docker_daemon_if_on_gcloud()] Skipped."
    fi
}

cpp_python_linking_uninstall_test() {
    # Expects the following environment variables to be set:
    # - DOCKER_TAG
    # - BUILD_SHARED_LIBS
    # - BUILD_CUDA_MODULE
    # - BUILD_PYTORCH_OPS
    # - BUILD_TENSORFLOW_OPS
    # - BUILD_SYCL_MODULE
    echo "[cpp_python_linking_uninstall_test()] DOCKER_TAG=${DOCKER_TAG}"
    echo "[cpp_python_linking_uninstall_test()] BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}"
    echo "[cpp_python_linking_uninstall_test()] BUILD_CUDA_MODULE=${BUILD_CUDA_MODULE}"
    echo "[cpp_python_linking_uninstall_test()] BUILD_PYTORCH_OPS=${BUILD_PYTORCH_OPS}"
    echo "[cpp_python_linking_uninstall_test()] BUILD_TENSORFLOW_OPS=${BUILD_TENSORFLOW_OPS}"
    echo "[cpp_python_linking_uninstall_test()] BUILD_SYCL_MODULE=${BUILD_SYCL_MODULE}"

    # Config-dependent argument: gpu_run_args
    if [ "${BUILD_CUDA_MODULE}" == "ON" ]; then
        docker_run="docker run --gpus all"
    else
        docker_run="docker run"
    fi

    # Config-dependent argument: pytest_args
    if [ "${BUILD_PYTORCH_OPS}" == "OFF" ] || [ "${BUILD_TENSORFLOW_OPS}" == "OFF" ]; then
        pytest_args="--ignore python/test/ml_ops/"
    else
        pytest_args=""
    fi
    restart_docker_daemon_if_on_gcloud

    # C++ test
    echo "gtest is randomized, add --gtest_random_seed=SEED to repeat the test sequence."
    ${docker_run} -i --rm ${DOCKER_TAG} /bin/bash -c " \
        cd build \
     && ./bin/tests --gtest_shuffle --gtest_filter=-*Reduce*Sum* \
    "
    restart_docker_daemon_if_on_gcloud

    # Python test
    echo "pytest is randomized, add --randomly-seed=SEED to repeat the test sequence."
    ${docker_run} -i --rm "${DOCKER_TAG}" /bin/bash -c " \
        python -m pytest python/test ${pytest_args} -s \
    "
    restart_docker_daemon_if_on_gcloud

    # Command-line tools test
    echo "testing Open3D command-line tools"
    ${docker_run} -i --rm "${DOCKER_TAG}" /bin/bash -c "\
        open3d \
     && open3d -h \
     && open3d --help \
     && open3d -V \
     && open3d --version \
     && open3d example -h \
     && open3d example --help \
     && open3d example -l \
     && open3d example --list \
     && open3d example -l io \
     && open3d example --list io \
     && open3d example -s io/image_io \
     && open3d example --show io/image_io \
    "

    # C++ linking with new project
    if [ "${BUILD_SYCL_MODULE}" == "ON" ]; then
        cmake_compiler_args="-DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx"
    else
        cmake_compiler_args=""
    fi

    ${docker_run} -i --rm "${DOCKER_TAG}" /bin/bash -c "\
        git clone https://github.com/isl-org/open3d-cmake-find-package.git \
     && cd open3d-cmake-find-package \
     && mkdir build \
     && pushd build \
     && echo Testing build with cmake \
     && cmake ${cmake_compiler_args} -DCMAKE_INSTALL_PREFIX=~/open3d_install .. \
     && make -j$(nproc) VERBOSE=1 \
     && ./Draw --skip-for-unit-test \
    "

    if [ "${BUILD_SHARED_LIBS}" == "ON" ] && [ "${BUILD_SYCL_MODULE}" == "OFF" ]; then
        ${docker_run} -i --rm "${DOCKER_TAG}" /bin/bash -c "\
            git clone https://github.com/isl-org/open3d-cmake-find-package.git \
         && cd open3d-cmake-find-package \
         && mkdir build \
         && pushd build \
         && echo Testing build with pkg-config \
         && export PKG_CONFIG_PATH=~/open3d_install/lib/pkgconfig \
         && echo Open3D build options: \$(pkg-config --cflags --libs Open3D) \
         && c++ ../Draw.cpp -o Draw \$(pkg-config --cflags --libs Open3D) \
         && ./Draw --skip-for-unit-test \
        "
    fi
    restart_docker_daemon_if_on_gcloud

    # Uninstall
    ${docker_run} -i --rm "${DOCKER_TAG}" /bin/bash -c "\
        cd build \
     && make uninstall \
    "
}

if [[ "$#" -ne 1 ]]; then
    echo "Error: invalid number of arguments." >&2
    print_usage_and_exit_docker_test
fi
echo "[$(basename $0)] building $1"
source "${HOST_OPEN3D_ROOT}/docker/docker_build.sh"
case "$1" in
# OpenBLAS AMD64
openblas-amd64-py36-dev)
    openblas_export_env amd64 py36 dev
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-amd64-py37-dev)
    openblas_export_env amd64 py37 dev
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-amd64-py38-dev)
    openblas_export_env amd64 py38 dev
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-amd64-py39-dev)
    openblas_export_env amd64 py39 dev
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-amd64-py36)
    openblas_export_env amd64 py36
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-amd64-py37)
    openblas_export_env amd64 py37
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-amd64-py38)
    openblas_export_env amd64 py38
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-amd64-py39)
    openblas_export_env amd64 py39
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;

# OpenBLAS ARM64
openblas-arm64-py36-dev)
    openblas_export_env arm64 py36 dev
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-arm64-py37-dev)
    openblas_export_env arm64 py37 dev
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-arm64-py38-dev)
    openblas_export_env arm64 py38 dev
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-arm64-py39-dev)
    openblas_export_env arm64 py39 dev
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-arm64-py36)
    openblas_export_env arm64 py36
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-arm64-py37)
    openblas_export_env arm64 py37
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-arm64-py38)
    openblas_export_env arm64 py38
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;
openblas-arm64-py39)
    openblas_export_env arm64 py39
    openblas_print_env
    cpp_python_linking_uninstall_test
    ;;

# CPU CI
cpu-static)
    cpu-static_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;
cpu-shared)
    cpu-shared_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;
cpu-shared-release)
    cpu-shared-release_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;
cpu-shared-ml)
    cpu-shared-ml_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;
cpu-shared-ml-release)
    cpu-shared-ml-release_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;

# SYCL CI
sycl-shared)
    sycl-shared_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;
sycl-static)
    sycl-static_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;

# ML CIs
2-bionic)
    2-bionic_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;
3-ml-shared-bionic)
    3-ml-shared-bionic_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;
3-ml-shared-bionic-release)
    3-ml-shared-bionic-release_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;
4-shared-bionic)
    4-shared-bionic_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;
4-shared-bionic-release)
    4-shared-bionic-release_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;
5-ml-focal)
    5-ml-focal_export_env
    ci_print_env
    cpp_python_linking_uninstall_test
    ;;

*)
    echo "Error: invalid argument: ${1}." >&2
    print_usage_and_exit_docker_test
    ;;
esac

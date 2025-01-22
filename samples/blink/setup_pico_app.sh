#!/bin/bash

show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  -p <hash>     Specify a hash value of zig_pico_cmake package"
    echo "  -d <directory> Specify a directory path of zig_pico_cmake package"
    exit 0
}

# set HASH and DIRECTORY to empty
HASH=""
DIRECTORY=""

if [[ $# -eq 0 ]]; then
    show_help
fi

if [[ $# -ne 2 ]]; then
    echo "Error: Only one parameter should be provided."
    show_help
    exit 1
fi

case $1 in
    -h|--help)
        show_help
        ;;
    -p)
        shift
        if [[ -z "$1" ]]; then
            echo "Error: -p requires a hash value argument."
            exit 1
        fi
        HASH=$1
        ;;
    -d)
        shift
        if [[ -z "$1" ]]; then
            echo "Error: -d requires a directory path argument."
            exit 1
        fi
        DIRECTORY=$1
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac

if [[ -n "$HASH" ]]; then
    cp ~/.cache/zig/p/$HASH/CMakeLists.txt .
    cp -r ~/.cache/zig/p/$HASH/config .
elif [[ -n "$DIRECTORY" ]]; then
    ln -sf $DIRECTORY/CMakeLists.txt
    ln -sf $DIRECTORY/config
else
    echo "Error: Either -p or -d must be provided."
    show_help
    exit 1
fi

echo "done"

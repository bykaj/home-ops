#!/bin/bash

RCFILES="/config/*"
for rcfile in $RCFILES; do
    echo "Processing ${rcfile}..."

    filename=$(basename -- "${rcfile}")

    mkdir -p "/backup/${filename}/new"
    mkdir -p "/backup/${filename}/cur"
    mkdir -p "/backup/${filename}/tmp"

    getmail --getmaildir "/backup/${filename}/" --rcfile "/config/${filename}"
done
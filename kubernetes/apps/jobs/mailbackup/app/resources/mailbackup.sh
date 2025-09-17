#!/bin/bash

RCFILES="/config/*"
for rcfile in $RCFILES; do
    echo "Processing ${rcfile}..."

    filename=$(basename -- "${rcfile}")

    mkdir -p "/data/Kaj/${filename}/new"
    mkdir -p "/data/Kaj/${filename}/cur"
    mkdir -p "/data/Kaj/${filename}/tmp"

    getmail --getmaildir "/data/Kaj/${filename}/" --rcfile "/config/${filename}"
done
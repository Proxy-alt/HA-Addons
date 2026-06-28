#!/bin/bash
# Mock implementation of the bashio library for testing.
# Only defines functions actually called by run.sh scripts.

bashio::log.info()  { :; }
bashio::log.error() { echo "[ERROR] $*" >&2; }
bashio::log.fatal() { echo "[FATAL] $*" >&2; }

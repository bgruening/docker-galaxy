#!/bin/bash
# cp tool_conf.xml config
export GALAXY_CONFIG_TOOL_CONFIG_FILE=/galaxy/tool_conf.xml
/usr/bin/startup
tailf /home/galaxy/logs/*

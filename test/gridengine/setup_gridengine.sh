#!/bin/bash

# hostname > /var/lib/gridengine/default/common/act_qmaster
/etc/init.d/gridengine-master start
/etc/init.d/gridengine-exec start

cat << EOS  > /tmp/qconf-ae.txt
hostname              $(hostname)
load_scaling          NONE
complex_values        NONE
user_lists            NONE
xuser_lists           NONE
projects              NONE
xprojects             NONE
usage_scaling         NONE
report_variables      NONE
EOS

qconf -Ae /tmp/qconf-ae.txt


# Add submit host
qconf -as `hostname`

# shell bash
cat << EOS > /tmp/qconf-aq.txt
qname                 testq
hostlist              $(hostname)
seq_no                0
load_thresholds       np_load_avg=1.75
suspend_thresholds    NONE
nsuspend              1
suspend_interval      00:05:00
priority              0
min_cpu_interval      00:05:00
processors            UNDEFINED
qtype                 BATCH INTERACTIVE
ckpt_list             NONE
pe_list               make
rerun                 FALSE
slots                 1
tmpdir                /tmp
shell                 /bin/bash
prolog                NONE
epilog                NONE
shell_start_mode      posix_compliant
starter_method        NONE
suspend_method        NONE
resume_method         NONE
terminate_method      NONE
notify                00:00:60
owner_list            NONE
user_lists            NONE
xuser_lists           NONE
subordinate_list      NONE
complex_values        NONE
projects              NONE
xprojects             NONE
calendar              NONE
initial_state         default
s_rt                  INFINITY
h_rt                  INFINITY
s_cpu                 INFINITY
h_cpu                 INFINITY
s_fsize               INFINITY
h_fsize               INFINITY
s_data                INFINITY
h_data                INFINITY
s_stack               INFINITY
h_stack               INFINITY
s_core                INFINITY
h_core                INFINITY
s_rss                 INFINITY
h_rss                 INFINITY
s_vmem                INFINITY
h_vmem                INFINITY
EOS

qconf -Aq /tmp/qconf-aq.txt

# avoid 'stdin: is not a tty'
sed -i -e 's/^mesg n//' /root/.profile

# echo "hostname ; date" | qsub


#
for HOST in $@
do
  qconf -as $HOST
done

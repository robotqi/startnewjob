#!/bin/csh -f

#
#NAME
#	start_new_job.csh	
#	
#DESCRIPTION
#	Copies an existing job, and clean it up to start a new order
#	for the same part number.
#
#	
#
#CALLING SCRIPT[S]
#	N/A
#
#CALLED SCRIPT[S]
#	$GENESIS_DIR/.ceirc			[main resources file]
#	
#
#RELATED FILES
#	N/A
#
#AUTHOR
#	Salah Elezaby, Automation Consultant
#
#HISTORY
#	02/22/08	: Version 1.00	: SE
#			
#	02/25/08	: Version 1.01	: SE
#			CHANGES:
#			o Update both Job Number and Control Number Attributes,
#			  according to the new values entered by the operator.
#			
#	02/26/08	: Version 1.02	: SE
#			CHANGES:
#			o Copy the "info.source" file in the "user" directory,
#			  as it is needed for the original panelization script.
#
#
#####################################################################################

set ver_num = "[Version 1.02]"

if (! $?SCR_DIR) then
	set SCR_DIR = $GENESIS_DIR/sys/scripts
endif

source $SCR_DIR/.ceirc

set msg_txt = ""
set msg_color = 888888
set orig_job = ""
set new_job = ""
set job_num = ""

SEL_JOB:
echo "WIN 100 100\
Font hbr18\
BG 444444\
LABEL START NEW JOB               $ver_num\
BG $msg_color\
LABEL "$msg_txt"\
BG 888888\
FONT hbr14\
TEXT orig_job 5 Original Eng. Number: \
DTEXT orig_job $orig_job\
TEXT new_job 5 New Eng. Number       : \
DTEXT new_job $new_job\
TEXT job_num 5 New Job Number        : \
DTEXT job_num $job_num\
RADIO exit_stat 'Abort ...........................?  ' H 1 990000\
No\
Yes\
END" > /tmp/new_job$PID

$GENESIS_EDIR/all/gui /tmp/new_job$PID > /tmp/new_job.gui$PID
source /tmp/new_job.gui$PID
rm /tmp/new_job$PID /tmp/new_job.gui$PID

if ($exit_stat == 2) then
	exit (0)
endif

if ("$orig_job" == "" || "$new_job" == "" || "$job_num" == "") then
	set msg_txt = "PLEASE FILL ALL FIELDS AND CONTINUE"
	set msg_color = 990000
	goto SEL_JOB
endif

DO_INFO -t job -e $orig_job -d EXISTS
if ($gEXISTS == no) then
	set msg_txt = "JOB $orig_job DOES NOT EXISTS"
	set msg_color = 990000
	goto SEL_JOB
endif

DO_INFO -t job -e $new_job -d EXISTS
if ($gEXISTS == yes) then
	set msg_txt = "JOB $new_job EXISTS. PLEASE DELETE IT FIRST"
	set msg_color = 990000
	goto SEL_JOB
endif

#
# Copy the original job, and strip the new job from some elements
#

COM open_job,job=$orig_job
COM close_form,job=$orig_job,form=cei_cam_pg1

# dscheuer 07/24/09:
# Changed code such that it now copies the panel step also.
#OLDCOM copy_stripped_job,source_job=$orig_job,dest_job=$new_job,dest_database=genesis,\
#OLDdel_elements=Forms,steps_mode=exclude,steps=$PNL_WRK,lyrs_mode=exclude,lyrs=
COM copy_stripped_job,source_job=$orig_job,dest_job=$new_job,dest_database=genesis,\
del_elements=Forms,steps_mode=exclude,steps=,lyrs_mode=exclude,lyrs=
COM close_job,job=$orig_job

COM open_job,job=$new_job
COM check_inout,mode=out,type=job,job=$new_job
# dscheuer 07/24/09:
# Changsd the code to not strip the panel
#Odd Code COM strip_job,job=$new_job,del_elements=Forms,steps_mode=exclude,steps=$PNL_WRK,lyrs_mode=exclude,lyrs=
COM strip_job,job=$new_job,del_elements=Forms,steps_mode=exclude,steps=,lyrs_mode=exclude,lyrs=

# Let make sure the environment is setup correctly, and that we are in the new job.
source $SCR_DIR/e_cam.rc
source $SCR_DIR/include_me

#
# Copy the standard forms
#

COM copy_form,src_job=genesislib,src_form=$PEC_FORM_ONE_LIBNAME,dst_job=$new_job,dst_form=$PEC_FORM_ONE_JOBNAME
COM copy_form,src_job=genesislib,src_form=$PEC_FORM_TWO_LIBNAME,dst_job=$new_job,dst_form=$PEC_FORM_TWO_JOBNAME
foreach form(rename lines clip)
	COM copy_form,src_job=genesislib,src_form=$form,dst_job=$new_job,dst_form=$form
end

# Make the the PEC version file is updated correctly. This is hardcoded because $JOB is
# not set for some reason.
echo "$CurrentPECVersion" >  $GENESIS_DIR/fw/jobs/$new_job/user/PECVersion

#
# Change the Job Number for the IPC Coupon
#

DO_INFO -t step -e $new_job/ipc -d EXISTS
if ($gEXISTS == yes) then
	COM set_attribute,type=job,job=$new_job,name1=,name2=,name3=,attribute=cexp_job,value=$job_num,units=inch
endif
COM set_attribute,type=job,job=$new_job,name1=,name2=,name3=,attribute=cexp_control,value=$new_job,units=inch
COM save_job,job=$new_job

COM check_inout,mode=in,type=job,job=$new_job
COM close_job,job=$new_job

COM open_job,job=$new_job
COM check_inout,mode=out,type=job,job=$new_job

#
# Rename Layers
#

DO_INFO -t matrix -e $new_job/matrix
@ row_num = 1
COM open_entity,job=$new_job,type=matrix,name=matrix,iconic=yes
while ($row_num <= $gNUM_ROWS)
	if ($gROWtype[$row_num] != empty) then
		set orig_name = $gROWname[$row_num]
		set new_name = `echo $orig_name | sed 's/'$orig_job'/'$new_job'/'`
		COM matrix_rename_layer,job=$new_job,matrix=matrix,layer=$orig_name,new_name=$new_name
	endif
	@ row_num++
end
COM matrix_page_close,job=$new_job,matrix=matrix

#
# Clean input directory (but keep some files)
#

pushd $GENESIS_DIR/fw/jobs/$new_job/input
	set inp_lst = (`ls`)
	foreach item($inp_lst)
		switch ($item)
			case $orig_job.zip:
				:
				breaksw
			default:
				rm -r $item
				breaksw
		endsw
	end
unzip $orig_job.zip ${orig_job}Tech.xls plot.txt refnet.ipcd
if (-e ${orig_job}Tech.xls) then
	mv ${orig_job}Tech.xls ${new_job}Tech.xls 
endif
popd

#
# Clean user directory (but keep info.source file)
#

pushd $GENESIS_DIR/fw/jobs/$new_job/user
	set usr_lst = (`ls`)
	foreach item($usr_lst)
		switch ($item)
			case info.source:
				:
				breaksw
			default:
				rm -r $item
				breaksw
		endsw
	end
popd


exit (0)


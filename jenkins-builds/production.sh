#!/bin/bash

# New modules will be added to xalt list (reversemap) at the end of this script, so one shouldn't use it as CI.
# The xalt list will be updated only by user jenkins, therefore this script can only be used by user jenkins.

# name of the script withouth the path
scriptname=$(basename $0)
# path to the folder containing the script
scriptdir=$(dirname $0)

usage() {
    echo -e "\n Usage: $0 [OPTIONS] -l <list> -p <prefix>
    -a,--arch         Architecture (gpu or mc)           (mandatory: Dom and Piz Daint only)
    -f,--force        Force build of item(s) in list     (optional: double quotes for multiple items)
    -h,--help         Help message
    -l,--list         Absolute path to production file   (mandatory: EasyBuild production list)
    -p,--prefix       Absolute path to EasyBuild prefix  (mandatory: installation folder)
    -u,--unuse        Module unuse colon separated PATH  (optional: default is null)
    -x,--xalt         [yes|no] update XALT database      (optional: default is yes)
    --hide-deps       Force hide modules listed in 'hide-deps' (TestingEB only)
    --exit-on-error   Exit when an error occurs (TestingEB only)
    "
    exit 1;
}

longopts="arch:,force:,help,list:,prefix:,unuse:,xalt:,hide-deps,exit-on-error"
shortopts="a:,f:,h,l:,p:,u:,x:"
eval set -- $(getopt -o ${shortopts} -l ${longopts} -n ${scriptname} -- "$@" 2> /dev/null)

eb_files=()
eb_lists=()
while [ $# -ne 0 ]; do
    case $1 in
        -a | --arch)
            shift
            ARCH="$1"
            ;;
        -f | --force)
            shift
            force_list="$1"
            ;;
        -h | --help)
            usage
            ;;
        -l | --list)
            shift
            mapfile -O ${#eb_files[@]} -t eb_files < $1
            eb_lists+=($1)
            ;;
        -p | --prefix)
            shift
            PREFIX="$1"
            ;;
        -u | --unuse)
            shift
            unuse_path="$1"
            ;;
        -x | --xalt)
            shift
            update_xalt_table={$1,,}
            ;;
        --exit-on-error)
            exit_on_error=true
            ;;
        --hide-deps)
            hidden_deps=true
            ;;
        --)
            ;;
        *)
            usage
            ;;
    esac
    shift
done


# checks force_list
if [ -n "${force_list}" ] && [ -n "${eb_lists}" ]; then
# match force_list items with production lists: only matching items will be built using the EasyBuild flag '-f'
 echo -e "Items matching production list and system filtered forcelist (\"${force_list}\")"
 for item in ${force_list}; do
     force_match=$(grep $item ${eb_lists[@]})
     if [ -n "${force_match}" ]; then
# 'grep -n' returns the 1-based line number of the matching pattern within the input file
         index_list=$(cat ${eb_lists[@]} | grep -n $item | awk -F ':' '{print $(NF-1)-1}')
# append the force flag '-f' to matching items within the selected production lists
         for index in ${index_list}; do
             eb_files[$index]+=" -f"
             echo "${eb_files[$index]}"
         done
     fi
 done
fi


# optional EasyBuild arguments
eb_args=""

# system name (excluding node number)
if [[ "$HOSTNAME" =~ arolla || "$HOSTNAME" =~ tsa ]]; then
 export system=${HOSTNAME%%-[cl]n[0-9]*}
elif [[ "$HOSTNAME" =~ uan0[1-3] ]]; then
 export system="eiger"
elif [[ "$HOSTNAME" =~ uan0[4-6] ]]; then
 export system="pilatus"
else
 export system=${HOSTNAME%%[0-9]*}
fi

# --- SYSTEM SPECIFIC SETUP ---
if [[ "$system" =~ "daint" || "$system" =~ "dom" ]]; then
# architecture (Dom and Piz Daint only)
    if [ -z "$ARCH" ]; then
        echo -e "\n No architecture defined. Please use the option -a,--arch to define the architecture \n"
        usage
    else
        module purge
        module load craype craype-network-aries modules perftools-base ugni cray-mpich
        module load daint-${ARCH}
        eb_args="${eb_args} --modules-header=${scriptdir%/*}/login/daint-${ARCH}.h --modules-footer=${scriptdir%/*}/login/daint.footer"
    fi
# xalt table update for Piz Daint
    if [ -z "$update_xalt_table" ]; then
        update_xalt_table=yes
    fi
fi

# --- COMMON SETUP ---
# set production repository folder
if [ -z "$EB_CUSTOM_REPOSITORY" ]; then
    export EB_CUSTOM_REPOSITORY=/apps/common/UES/jenkins/production/easybuild
fi
# module unuse PATH before loading EasyBuild module and building
if [ -n "$unuse_path" ]; then
 echo -e " Unuse path: $unuse_path "
 module unuse $unuse_path
 echo -e " Updated MODULEPATH: $MODULEPATH "
fi
# check prefix folder
if [ -z "$PREFIX" ]; then
    echo -e "\n Prefix folder not defined. Please use the option -p,--prefix to define the prefix folder \n"
    usage
else
 export EASYBUILD_PREFIX=$PREFIX
# create a symbolic link to EasyBuild-custom/cscs if not found in $EASYBUILD_PREFIX/modules/all
 if [ ! -e "$EASYBUILD_PREFIX/modules/all/EasyBuild-custom/cscs" ]; then
  mkdir -p "$EASYBUILD_PREFIX/modules/all"
  mkdir -p "$EASYBUILD_PREFIX/tools/modules/all"
  ln -s /apps/common/UES/jenkins/production/easybuild/module/EasyBuild-custom $EASYBUILD_PREFIX/modules/all
 fi
# check if PREFIX is already in MODULEPATH after unuse command
 statuspath=$(echo $MODULEPATH | grep -c $EASYBUILD_PREFIX)
 if [ $statuspath -eq 0 ]; then
  echo -e " Use path (EASYBUILD_PREFIX): $EASYBUILD_PREFIX/modules/all "
  module use $EASYBUILD_PREFIX/modules/all
  echo -e " Updated MODULEPATH: $MODULEPATH "
 fi
fi

# --- BUILD ---
# load module EasyBuild-custom
module load EasyBuild-custom/cscs

# add hidden flag
if [ -n "${eb_lists}" ] && [ -n "${hidden_deps}" ]; then
  __eb_list=`eb --show-full-config | grep -i hide | awk -F'=' '{print $2}' | head -1`
  IFS=', ' read -r -a hidden_deps <<< ${__eb_list}

# match  items with hide deps list: matching items will be built using the EasyBuild flag '--hidden'
 echo -e "Items matching hidden list and easybuild recipes to install (\"${eb_lists}\")"
 for item in ${hidden_deps[@]}; do
     hidden_match=$(grep $item ${eb_lists[@]})
     if [ -n "${hidden_match}" ]; then
# 'grep -n' returns the 1-based line number of the matching pattern within the input file
         index_list=$(cat ${eb_lists[@]} | grep -n $item | awk -F ':' '{print $(NF-1)-1}')
# append the --hidden flag to matching items within the selected build list
         for index in ${index_list}; do
             eb_files[$index]+=" --hidden"
             echo "${eb_files[$index]}"
         done
     fi
 done
fi

# print EasyBuild configuration, module list, production file(s), list of builds
echo -e "\n EasyBuild version and configuration ('eb --version' and 'eb --show-config'): "
echo -e " $(eb --version) \n $(eb --show-config) \n"
echo -e " Modules loaded ('module --terse list'): "
echo -e " $(module --terse list)"
echo -e " Production file(s): ${eb_lists[@]} \n"
echo -e " List of builds (including options):"
for ((i=0; i<${#eb_files[@]}; i++)); do
# use eval to expand environment variables in the EasyBuild options of each build
    eb_files[i]=$(eval echo ${eb_files[i]})
    echo ${eb_files[$i]}
done

# checks dependency list using dry run
dryrun=$(eb ${eb_files[@]} -Dr ${eb_args} 2>&1)
if [[ "$dryrun" =~ "ERROR" ]]; then
 echo -e "$dryrun" | grep "ERROR"
 exit 1
#else
# # list of production builds including dependencies
# echo -e " List of builds (including dependencies):"
# echo "$dryrun" | awk '$1~/\*/{sub(/\$.*\//,"",$(NF-2)); print $(NF-2)}'
fi

# start time
echo -e "\n Starting ${system} builds on $(date)"
starttime=$(date +%s)

# cumulative exit status of EasyBuild commands in the loop
status=0
# loop over the list of EasyBuild files to build
for((i=0; i<${#eb_files[@]}; i++)); do
    echo -e "\n===============================================================\n"
# define name and version of the current build starting from the recipe name (obtained removing EasyBuild options from eb_files)
    recipe=$(echo ${eb_files[$i]} | cut -d' ' -f 1)
    name=$(echo $recipe | cut -d'-' -f 1)
# build licensed software (CPMD, IDL, MATLAB, VASP) on Dom and Piz Daint
    if [[ "$name" =~ "CPMD" || "$name" =~ "IDL" ||  "$name" =~ "MATLAB" || "$name" =~ "VASP" ]] && [[ "$system" =~ "daint" || "$system" =~ "dom" ]]; then
        version=$(echo $recipe | sed -e "s/^${name}-//" -e "s/.eb//")
# custom footer for ${name} modulefile with a warning for users not belonging to corresponding group
        if [[ "$name" =~ "IDL" ]]; then
        # check IDL version
            if [[ "$version" =~ "CSCS" ]]; then
                group="${name,,}cscs"
            else
                group="${name,,}ethz"
            fi
        elif [[ "$name" =~ "VASP" ]]; then
        # check VASP version
            if [[ "$version" =~ "5.4" ]]; then
                group="${name,,}"
            else
                # group vasp6 enforced after June 30th 2020"
                group="${name,,}6"
            fi
        else
            group=${name,,}
        fi
        footer="if { [lsearch [exec groups] \"${group}\"]==-1 && [module-info mode load] } {
 puts stderr \"WARNING: Only users belonging to group ${group} with a valid ${name} license are allowed to access ${name}/${version} executables and library files\"
}"
        (cat ${scriptdir%/*}/login/daint.footer; echo "$footer") > ${EASYBUILD_TMPDIR}/${name}.footer
        echo -e "eb ${eb_files[$i]} -r ${eb_args} --modules-footer=${EASYBUILD_TMPDIR}/${name}.footer\n"
        eb ${eb_files[$i]} -r ${eb_args} --modules-footer=${EASYBUILD_TMPDIR}/${name}.footer
        status=$[status+$?]
        # check current group ownership of the licensed software directory created by EasyBuild
        checkgroup=$(stat -c "%G" ${EASYBUILD_INSTALLPATH}/software/${name}/${version})        
        if [ "$checkgroup" != "$group" ]; then 
        # change group ownership: note that $USER needs to be a member of the group to use the command chgrp
            echo -e "\n Changing group ownership of the folder ${EASYBUILD_INSTALLPATH}/software/${name}/${version} to ${group}"
            chgrp ${group} -R ${EASYBUILD_INSTALLPATH}/software/${name}/${version}
        fi
        # check current access rights of the licensed software directory created by EasyBuild: last digit must be 0 (no access rights for others)
        checkrights=$(stat -c "%a" ${EASYBUILD_INSTALLPATH}/software/${name}/${version})        
        if [ ${checkrights: -1} -ne 0 ]; then 
        # change access rights: note that $USER needs to own the folder to use the command chmod
            echo -e "\n Removing access rights to the folder ${EASYBUILD_INSTALLPATH}/software/${name}/${version} for others"
            chmod -R o-rwx ${EASYBUILD_INSTALLPATH}/software/${name}/${version}
        fi
# build xalt on Dom and Piz Daint
    elif [[ "$name" =~ "xalt" ]] && [[ "$system" =~ "daint" || "$system" =~ "dom" ]]; then
        module unload xalt
        echo -e "eb ${eb_files[$i]} -r"
        eb ${eb_files[$i]} -r
        status=$[status+$?]
        module load xalt
# build other software on every system
    else
        echo -e "eb ${eb_files[$i]} -r ${eb_args}"
        eb ${eb_files[$i]} -r ${eb_args}
        status=$[status+$?]
    fi
    if [ -n "${exit_on_error}" ] && [ "X$status" != "X0" ]; then
        exit 1
    fi
done

# --- SYSTEM SPECIFIC POST-PROCESSING ---
if [[ $system =~ "daint" && $update_xalt_table =~ "y" ]]; then
# update xalt table of modulefiles
    echo "loading PrgEnv-cray"
    module load PrgEnv-cray
# removing Easybuild module before the reverseMapD operation
    module unload Easybuild
    userid=$(id -u)
    echo "check if will run reverseMapD"
# commands run by jenscscs user only
    #if [ $userid -eq 23395 ]; then
    #    echo "running reverseMapD"
    #    module load Lmod/.7.8.2
    #    export PATH=$EBROOTLMOD/lmod/7.1/libexec:$PATH  # !!! for spider !!!
    #    export XALTJENKINS=/apps/daint/UES/xalt/JENSCSCS
    #    export XALTPROD=/apps/daint/UES/xalt/production
    #    cd $XALTJENKINS/
    #    rm -rf $XALTJENKINS/reverseMapD
    #    ./cray_build_rmapT.sh .
    #    cp ./reverseMapD/*    $XALTPROD/etc/reverseMapD/
    #    cd -
    #fi
fi

# end time
endtime=$(date +%s)
# time difference
difftime=$(($endtime-$starttime))
# convert seconds to hours minutes seconds format
 ((h=${difftime}/3600))
 ((m=(${difftime}%3600)/60))
 ((s=${difftime}%60))
echo -e "\n Builds ended on $(date) (elapsed time is $difftime s : ${h}h ${m}m ${s}s) \n"

# cumulative exit status of all the builds and the last command
exit $[status+$?]

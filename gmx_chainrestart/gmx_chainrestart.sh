#!/bin/bash
################################################################################ 
# Automation for running GROMACS jobs that require restarts on NERSC           #
# Copyright (C) 2015  John Haberstroh                                          #
#                                                                              #
# This program is free software; you can redistribute it and/or                #
# modify it under the terms of the GNU General Public License                  #
# as published by the Free Software Foundation; either version 2               #
# of the License, or (at your option) any later version.                       #
#                                                                              #
# This program is distributed in the hope that it will be useful,              #
# but WITHOUT ANY WARRANTY; without even the implied warranty of               #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                #
# GNU General Public License for more details.                                 #
#                                                                              #
# You should have received a copy of the GNU General Public License            #
# along with this program; if not, write to the Free Software                  #
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA #
################################################################################ 
# Requires: 
#   gromacs.sh in same directory
################################################################################ 
# Optional args: 
#  GMX__CPT              : int, number of minutes between checkpoints
#  PBS__NEXT_JOB_COUNTER : int, set >1 to restart from non-first chain link
################################################################################ 
# Usage:                                                                       #
#   Call script with $1 set to .cfg file (see example file).                   #
#   Script will create an output directory with basename of .cfg file (e.g. if #
#   run with "test.cfg", will create a dir named "test" for PBS output in the  #
#   same directory as "test.cfg").                                             #
################################################################################ 

#PBS -j oe

set -o errexit
set -o nounset

################################################################################ 
# 1. Submit job to the PBS queue (original or restart)
#   Extra vars passed to job: 
#    - PBS__JOBNAME: name for job parsed from .cfg file
#    - OPT_NUMBER: PBS__JOBNAME modifier for resubmitting runs on the 
#                  same cfg 
#    - PBS__JOB_COUNTER: int counter for which job repeat
#    - PBS__NEXT_JOB_COUNTER: int counter for which job repeat
#    - SRCDIR: abs path to this script
#
# This section can easily be adapted to other automated rerun scripts.
# Variables labeled with GMX are those that are gromacs specific.
# Two underscores (__) is used to denote script specific variables and
# avoid conflict with built in $PBS and $GMX variables.
################################################################################ 

################################################################################ 
# IF ON HEAD NODE: Submit the first job with PBS__JOB_COUNTER=1
if [ -z ${PBS_JOBID+x} ]; then
    # Check for config file passed as $1 arg, source it
    echo "Loading ${1?ERROR: No config file passed in \$1}"
    if [ ${1%*.cfg} == $1 ]; then
        echo "ERROR: Must pass \$1 as a file with .cfg extension"
        exit
    fi
    # source .cfg and check that all vital variables have been loaded
    . $1
    # APPLICATION SPECIFIC: change to variables needed for your script
    export    PBS__NPROCS=${PBS__NPROCS?ERROR: var not set in config}
    export PBS__MAXSUBMIT=${PBS__MAXSUBMIT?ERROR: var not set in config}
    export     PBS__QUEUE=${PBS__QUEUE?ERROR: var not set in config}
    export  PBS__WALLTIME=${PBS__WALLTIME?ERROR: var not set in config}
    export         grompp=${grompp?ERROR: var not set in config}
    export          mdrun=${mdrun?ERROR: var not set in config}
    export    GMX__OLDGRO=${GMX__OLDGRO?ERROR: var not set in config}
    export    GMX__OUTDIR=${GMX__OUTDIR?ERROR: var not set in config}
    export   GMX__CONFDIR=${GMX__CONFDIR?ERROR: var not set in config}
    export    GMX__MDPDIR=${GMX__MDPDIR?ERROR: var not set in config}
    export       GMX__MDP=${GMX__MDP?ERROR: var not set in config}
    export   GMX__TOPNAME=${GMX__TOPNAME?ERROR: var not set in config}
    # Create the output directory if it does not exist
    if [ ! -e $GMX__OUTDIR ]; then
        mkdir -p $GMX__OUTDIR
    elif [ ! -d $GMX__OUTDIR ]; then
        echo "\$GMX__OUTDIR: $GMX__OUTDIR exists but is not a dir!"
        exit 1
    fi
    
    # Build jobname from name of config file
    export     GMX__CPT=${GMX__CPT-5}
    export   OPT_NUMBER=${2-}
    export PBS__JOBNAME=${1%.cfg}
    export PBS__NEXT_JOB_COUNTER=${PBS__NEXT_JOB_COUNTER-1}
    if [ ! -d $PBS__JOBNAME ]; then
        mkdir $PBS__JOBNAME
    fi
    export SRCDIR=$( cd "$( dirname "$0" )" && pwd )
    
    # Call qsub with -V, passing all set variables to the job
    qsub $SRCDIR/gmx_chainrestart.sh \
        -q $PBS__QUEUE \
        -l walltime=$PBS__WALLTIME \
        -N $PBS__JOBNAME-$OPT_NUMBER-$PBS__NEXT_JOB_COUNTER \
        -o $PBS__JOBNAME/output-$OPT_NUMBER-$PBS__NEXT_JOB_COUNTER \
        -l mppwidth=$PBS__NPROCS \
        -V 
    exit

# IF ON MOM NODE: Inc the counter and submit a restart hold job 
else
    export PBS__JOB_COUNTER=$PBS__NEXT_JOB_COUNTER
    cd $PBS_O_WORKDIR
    echo JOB NUMBER $PBS__JOB_COUNTER
    export PBS__NEXT_JOB_COUNTER=$(echo "$PBS__JOB_COUNTER + 1" | bc)
    if [ $PBS__NEXT_JOB_COUNTER -le $PBS__MAXSUBMIT ]; then
        qsub $SRCDIR/gmx_chainrestart.sh \
            -q $PBS__QUEUE \
            -l walltime=$PBS__WALLTIME \
            -N $PBS__JOBNAME-$OPT_NUMBER-$PBS__NEXT_JOB_COUNTER \
            -o $PBS__JOBNAME/output-$OPT_NUMBER-$PBS__NEXT_JOB_COUNTER \
            -l mppwidth=$PBS__NPROCS \
            -V \
            -W depend=afternotok:$PBS_JOBID
    fi
fi
# ENDIF 
################################################################################ 


################################################################################ 
# 2. Primary execution block for mom node below this line 
################################################################################ 
# If no gromacs specified in config, use default gromacs
if [ -z $(module -t list 2>&1 | grep gromacs) ]; then
    module load gromacs/4.6.7-sp
fi

if [ "$PBS__JOB_COUNTER" -eq 1 ]; then
    # Run initialization job using $GMX__OLDGRO
    grompp=$grompp mdrun=$mdrun $SRCDIR/gromacs.sh \
        $GMX__OLDGRO \
        $GMX__CONFDIR/$GMX__TOPNAME.top \
        $GMX__CONFDIR/mdp \
        $GMX__OUTDIR \
        $GMX__MDP \
        "-n $GMX__CONFDIR/index.ndx"
else
    # Run continuation job (Second line specifies current .gro file)
    cd $GMX__OUTDIR
    $mdrun -v -cpi $GMX__OUTDIR/$GMX__MDP.cpt -s $GMX__OUTDIR/$GMX__MDP.tpr \
        -deffnm $GMX__MDP -cpt $GMX__CPT
    cd -
fi

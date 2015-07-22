#!/bin/bash
################################################################################ 
# Automation for running GROMACS jobs on NERSC
# Copyright (C) 2015  John Haberstroh
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
################################################################################ 
# EXAMPLE:
# gromacs $CONFDIR/4BCL $CONFDIR/4BCL.top $MDPDIR $EMDIR em_steep 
#  runs the following:
#   >> $grompp on [$CONFDIR/4BCL.gro, $CONFDIR/4BCL.top, $MDPDIR/em_steep.mdp]
#   >> $mdrun  on the output of that.
#  All output is put in $EMDIR under the name of em_steep.*
################################################################################ 

set -o errexit
set -o nounset

    OLDGRO=${1?var not set}
       TOP=${2?var not set}
    mdpdir=${3?var not set}
    NEWDIR=${4?var not set}
   NEWNAME=${5?var not set}
GROMPP_OPT=${6-}
 MDRUN_OPT=${7-}
  GMX__CPT=${GMX__CPT-5}

if [ -e $OLDGRO.cpt ]; then
    echo "Checkpoint file $OLDGRO.cpt found."
    $grompp -c $OLDGRO.gro -t $OLDGRO.cpt -p $TOP \
        -o $NEWDIR/$NEWNAME -f $mdpdir/$NEWNAME -po $NEWDIR/$NEWNAME $GROMPP_OPT
else
    echo "WARNING: CHECKPOINT FILE $OLDGRO.cpt NOT FOUND!"
    echo "Confirm that this is the first run or make sure the file is located in the correct directory."
    $grompp -c $OLDGRO.gro -p $TOP -o $NEWDIR/$NEWNAME \
        -f $mdpdir/$NEWNAME -po $NEWDIR/$NEWNAME $GROMPP_OPT
fi

cd $NEWDIR
$mdrun -v -deffnm $NEWNAME -cpt $GMX__CPT $MDRUN_OPT
cd -

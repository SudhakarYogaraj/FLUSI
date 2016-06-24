#!/bin/bash

echo "***************************************************"
echo "Unit-testing script for flusi/mhd pseudospectators."
echo "***************************************************"

# this is to reduce the number of files in the repository
#tar xzf tests_data.tar.gz

# list all the test scrits you want, separated by spaces
tests=(solid_model.sh solid_model2.sh solid_model3.sh solid_model4.sh jerry.sh striding.sh
       fruitfly_mask.sh fruitfly_mask_movingbody.sh fruitfly_mask_kineloader.sh bumblebee_mask.sh scalar.sh
       vortexring1_AB2.sh
       vortexring2_RK2.sh vortexring4_sponge.sh
       sphere_sponge_RK2.sh sphere.sh sphere_restart.sh sphere_fall_fsi.sh mhdorszagtang.sh
       swimmer1_iteration.sh swimmer2_staggered.sh swimmer3_semiimplicit.sh
       insect.sh insect_RK4.sh)

# link flusi and mhd from .. to . if this isn't already done.
if [ ! -f flusi ]; then
    ln -s ../flusi .
fi
if [ ! -f mhd ]; then
    ln -s ../mhd .
fi

if [ -z "$nprocs" ]; then
    nprocs=4
fi
if [ -z "$mpi_command" ]; then
    export mpi_command="nice -n 19 ionice -c 3 mpiexec --np ${nprocs}"
fi
if [ -z "$mpi_serial" ]; then
    export mpi_serial=""
fi

numtests=0
numsuccess=0
numfail=0

echo "employed command for parallel exec: " $mpi_command
echo "employed command for serial   exec: " $mpi_serial
echo "to modify these commands, set \$nprocs, \$mpi_command or \$mpi_serial in shell"

# Get time as a UNIX timestamp (seconds elapsed since Jan 1, 1970 0:00 UTC)
T="$(date +%s)"

for test in ${tests[*]}
do
    numtests=$(($numtests + 1))

    logfile=${test%%.sh}.log
    rm -f $logfile
    touch $logfile

    # run the test, copy the output to the logfile
    ./$test > $logfile
    success=$?
    if [ $success == 0 ]
    then
	echo -e "OK\tRunning test: "${test}", log in: "${logfile}
	numsuccess=$(($numsuccess + 1))
    else
	echo -e "FAIL\tRunning test: "${test}", log in: "${logfile}
	numfail=$(($numfail + 1))
    fi

    #cleanup
    rm -f *.key
    rm -f *.h5
    rm -f drag_data
    rm -f *.t end IBES_iter
    rm -f runtime*.ini
    rm -f success
    rm -f deco*
done

echo
T="$(($(date +%s)-T))"
echo "Time used in tests: ${T} seconds"

echo
echo "Total number of tests: " $numtests
echo "Total number successful: " $numsuccess
echo "Total number failed: " $numfail

if [ $numfail -gt 0 ]
then
    echo "NOT ALL TESTS PASSED: DANGER! DANGER!"
fi

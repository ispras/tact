#!/bin/bash


if [ "x$SPEC_DIR" == "x" ]; then echo "You should export path to your spec2000 as SPEC_DIR !"; exit 1; fi
if [ "x$TACT_DIR" == "x" ]; then echo "You should run set-env first!"; exit 1; fi

APPS=(175.vpr  176.gcc  181.mcf  186.crafty  197.parser  252.eon  253.perlbmk  254.gap  255.vortex  256.bzip2  300.twolf)

for app in "${APPS[@]}"
do
	rm -rf $TACT_DIR/apps/$app
	mkdir -p $TACT_DIR/apps/$app/tests/default/bin/
	mkdir -p $TACT_DIR/apps/$app/tests/default/etc/
	mkdir -p $TACT_DIR/apps/$app/tests/default/private-bin/
	mkdir -p $TACT_DIR/apps/$app/tests/default/private-etc/
	mkdir -p $TACT_DIR/apps/$app/data/
	mkdir -p $TACT_DIR/apps/$app/bin/
	
	cp $TACT_DIR/specstrap/init-pool $TACT_DIR/apps/$app/tests/default/bin/
	cp $TACT_DIR/specstrap/init-pool $TACT_DIR/apps/$app/tests/default/bin/rebuild-pool
	cp $TACT_DIR/specstrap/compute-size $TACT_DIR/apps/$app/tests/default/bin/
	cp $TACT_DIR/specstrap/parse-results.rb $TACT_DIR/apps/$app/tests/default/bin/
	cp $TACT_DIR/specstrap/target-run-test $TACT_DIR/apps/$app/tests/default/bin/

	cp $TACT_DIR/specstrap/tuning.conf $TACT_DIR/apps/$app/tests/default/etc/
	cp $TACT_DIR/specstrap/test-descr.xml $TACT_DIR/apps/$app/tests/default/etc/

	cp -r $SPEC_DIR/benchspec/CINT2000/$app/src $TACT_DIR/apps/$app/
	cp $SPEC_DIR/benchspec/Makefile.defaults $TACT_DIR/apps/$app/tests/default/
	cp -r $SPEC_DIR/benchspec/CINT2000/$app/data/ $TACT_DIR/apps/$app/

	cp $TACT_DIR/specstrap/verify-results $TACT_DIR/apps/$app/bin/
	cp $TACT_DIR/specstrap/compute-binary-hash $TACT_DIR/apps/$app/bin/

	cp $TACT_DIR/specstrap/$app/target-run-single-test $TACT_DIR/apps/$app/tests/default/private-bin/

	echo "spec" > $TACT_DIR/apps/$app/tests/default/private-etc/test-set
done


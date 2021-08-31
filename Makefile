libtil_vm.so: source/app.d
	dub build --compiler=ldc2

run: libtil_vm.so
	dub run til:run -b release --compiler=ldc2 -- test.til

debug: libtil_vm.so
	dub run til:run -b debug --compiler=ldc2 -- test.til

dist/libtil_vm.so: til source/app.d
	ldc2 --shared source/app.d \
		-I=til/source \
		-link-defaultlib-shared \
		-L-L${PWD}/dist -L-L${PWD}/til/dist -L-ltil \
		--O2 -of=dist/libtil_vm.so

test:
	til run test.til

til:
	git clone https://github.com/til-lang/til.git til

clean:
	-rm dist/*.so

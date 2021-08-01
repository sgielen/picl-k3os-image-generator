container:
	docker build . -t picl-builder:latest

container_run:
	docker run --rm -e TARGET=all -v ${PWD}:/app -v /dev:/dev --privileged picl-builder:latest

container_clean:
	docker rmi picl-builder:latest

image:
	./build-image.sh all

burn:
	echo "not yet implemented"

clean:
	rm -rf deps/*


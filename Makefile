DOCKER_TAG = dev

.PHONY: all install clean

DEBIAN_BRANCH = debian

# For git-buildpackage's mysterious purposes we need to tell it the revision
# of the upstream branch we are building from.  (We can't just give it the
# branch name because Travis' git clone doesn't include branch refs.)
#
# XXX update this if you merge in new changes from upstream!  If you use
#     REVISION=origin/master make deb-merge
# instead of
#     git merge origin/master
# then this will be updated for you.
DEBIAN_UPSTREAM_TAG = 90a916a

all:
	$(MAKE) -C ext all
	$(MAKE) -C client all
	$(MAKE) -C kafka all

install:
	$(MAKE) -C ext install

clean:
	$(MAKE) -C ext clean
	$(MAKE) -C client clean
	$(MAKE) -C kafka clean


test-bundle: Gemfile.lock
	bundle install

spec/functional/type_specs.rb: spec/bin/generate_type_specs.rb test-bundle docker-compose
	bundle exec ruby -Ispec $< >$@

test: spec/functional/type_specs.rb
	bundle exec rspec --order random

docker: docker-client docker-postgres docker-postgres94

docker-compose: docker
	docker-compose build

tmp:
	mkdir tmp

tmp/%-94.tar.gz: tmp docker-build-94
	docker run --rm bwbuild-94:$(DOCKER_TAG) cat /$*-94.tar.gz > $@

tmp/%.tar.gz: tmp docker-build
	docker run --rm bwbuild:$(DOCKER_TAG) cat /$*.tar.gz > $@

tmp/%: build/% tmp
	cp $< $@

docker-build-94:
	docker build -f build/Dockerfile.build94 -t bwbuild-94:$(DOCKER_TAG) .

docker-build:
	docker build -f build/Dockerfile.build -t bwbuild:$(DOCKER_TAG) .

docker-client: tmp/Dockerfile.client tmp/avro.tar.gz tmp/librdkafka.tar.gz tmp/bottledwater-bin.tar.gz tmp/bottledwater-docker-wrapper.sh
	docker build -f $< -t local-bottledwater:$(DOCKER_TAG) tmp

docker-postgres: tmp/Dockerfile.postgres tmp/bottledwater-ext.tar.gz tmp/avro.tar.gz tmp/replication-config.sh
	docker build -f $< -t local-postgres-bw:$(DOCKER_TAG) tmp

docker-postgres94: tmp/Dockerfile.postgres94 tmp/bottledwater-ext-94.tar.gz tmp/avro.tar.gz tmp/replication-config.sh
	docker build -f $< -t local-postgres94-bw:$(DOCKER_TAG) tmp

deb-merge:
	test -n "${REVISION}" || { echo 'Please set the REVISION you want to merge (e.g. origin/master)' >&2; exit 1; }
	git rev-parse --short "${REVISION}" | xargs -I SHA sed -i 's/^\(DEBIAN_UPSTREAM_TAG\) = .*/\1 = SHA/' Makefile
	git commit -m "Set git-upstream to ${REVISION}" Makefile
	git merge "${REVISION}"

deb-snapshot:
	gbp dch --debian-branch=$(DEBIAN_BRANCH) --snapshot

deb-release:
	gbp dch --debian-branch=$(DEBIAN_BRANCH) --release --distribution=trusty --commit

deb-new-release:
	test -n "${VERSION}" || { echo 'Please set VERSION (e.g. 0.1++mybranch-0ubuntu1)' >&2; exit 1; }
	gbp dch --debian-branch=$(DEBIAN_BRANCH) --release --distribution=trusty "--new-version=${VERSION}" --commit

deb-chroot-vars:
	test -n "${DIST}" || { echo Please set DIST >&2; exit 1; }
	test -n "${ARCH}" || { echo Please set ARCH >&2; exit 1; }

deb-prepare: deb-chroot-vars
	git-pbuilder create --components 'main universe' --hookdir debian/pbuilder-hooks

deb-update: deb-chroot-vars
	git-pbuilder update --components 'main universe' --hookdir debian/pbuilder-hooks

deb-build: deb-chroot-vars
	sed -i "s:trusty:${DIST}:g" debian/changelog
	gbp buildpackage -us -uc --git-ignore-branch --git-upstream-tag=$(DEBIAN_UPSTREAM_TAG) --git-verbose --git-tag --git-ignore-new --git-pbuilder --git-arch=${ARCH} --git-dist=${DIST}

DOCKER_IMAGE = bwdeb
PBUILDER_CACHE = /tmp/pbuilder-cache

deb-docker:
	docker build -t $(DOCKER_IMAGE) --build-arg DEBIAN_BRANCH=$(DEBIAN_BRANCH) -f build/Dockerfile.debian .

deb-prepare-docker: deb-chroot-vars deb-docker
	docker run --rm --privileged=true -e DIST=${DIST} -e ARCH=${ARCH} -v $(PBUILDER_CACHE):/var/cache/pbuilder $(DOCKER_IMAGE) make deb-prepare

deb-update-docker: deb-chroot-vars deb-docker
	docker run --rm --privileged=true -e DIST=${DIST} -e ARCH=${ARCH} -v $(PBUILDER_CACHE):/var/cache/pbuilder $(DOCKER_IMAGE) make deb-update

deb-build-docker: deb-chroot-vars deb-docker
# not making deb-prepare-docker a dependency to avoid rebuilding the chroot every time
	docker run --rm --privileged=true -e DIST=${DIST} -e ARCH=${ARCH} -v $(PBUILDER_CACHE):/var/cache/pbuilder $(DOCKER_IMAGE) make deb-build

deb-clean-docker:
	sudo rm -rf $(PBUILDER_CACHE)

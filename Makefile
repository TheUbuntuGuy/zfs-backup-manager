STAGING_DIR=bin
PACKAGE_DIR=$(STAGING_DIR)/zfs-backup-manager
CONFIG_DIR=$(PACKAGE_DIR)/etc
BIN_DIR=$(PACKAGE_DIR)/usr/local/bin
DEBIAN_DIR=$(PACKAGE_DIR)/DEBIAN

.PHONY: all clean package directories stage test install

all: package

clean:
	rm -rf $(STAGING_DIR)

directories:
	mkdir -p $(STAGING_DIR)
	mkdir -p $(PACKAGE_DIR)
	mkdir -p $(CONFIG_DIR)
	mkdir -p $(BIN_DIR)
	mkdir -p $(DEBIAN_DIR)

stage: directories
	cp zfs-backup-manager.conf $(CONFIG_DIR)
	cp zfs-backup-manager.sh $(BIN_DIR)
	cp control $(DEBIAN_DIR)

package: directories stage
	$(eval SIZE := $(shell du -s "${PACKAGE_DIR}" | cut -f 1))
	sed -i "/Installed-Size/c\Installed-Size: ${SIZE}" $(DEBIAN_DIR)/control
	dpkg --build $(PACKAGE_DIR)
	rm -rf $(PACKAGE_DIR)

test:
	sudo ./test_zfs_backup_manager.sh

install: package
	sudo dpkg -i bin/zfs-backup-manager.deb

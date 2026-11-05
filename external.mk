# Copy the wireless regulatory database into the kernel tree so that CONFIG_EXTRA_FIRMWARE can build it in.
define RDM_BRIDGE_LINUX_REGDB
	mkdir -p $(LINUX_DIR)/firmware
	cp $(BR2_EXTERNAL_RDM_BRIDGE_PATH)/board/rdm_bridge/firmware/regulatory.db \
	   $(BR2_EXTERNAL_RDM_BRIDGE_PATH)/board/rdm_bridge/firmware/regulatory.db.p7s $(LINUX_DIR)/firmware/
endef
LINUX_PRE_BUILD_HOOKS += RDM_BRIDGE_LINUX_REGDB

#!/usr/bin/env rspec
# encoding: utf-8

# Copyright (c) [2017] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require_relative "spec_helper"
require "y2storage"

describe Y2Storage::BlkDevice do
  using Y2Storage::Refinements::SizeCasts

  before do
    fake_scenario(scenario)
  end

  subject(:device) { Y2Storage::BlkDevice.find_by_name(fake_devicegraph, device_name) }

  let(:scenario) { "complex-lvm-encrypt" }

  describe "#formatted?" do
    let(:device_name) { "/dev/sda" }

    context "when the device is not formatted" do
      it "returns false" do
        expect(device.formatted?).to eq(false)
      end
    end

    context "when the device is formatted" do
      let(:device_name) { "/dev/sda" }

      before do
        device.remove_descendants
        device.create_filesystem(Y2Storage::Filesystems::Type::EXT3)
      end

      it "returns true" do
        expect(device.formatted?).to eq(true)
      end
    end
  end

  describe "#delete_filesystem" do
    let(:scenario) { "md-imsm1-devicegraph.xml" }

    context "when the device is formatted" do
      let(:device_name) { "/dev/md/a" }

      it "removes the filesystem" do
        expect(device.filesystem).to_not be_nil
        device.delete_filesystem
        expect(device.filesystem).to be_nil
      end
    end

    context "when the device is not formatted" do
      let(:device_name) { "/dev/md/b" }

      it "does not modify the device" do
        children_before = device.children
        device.delete_filesystem
        expect(device.children).to eq(children_before)
      end
    end
  end

  describe "#plain_device" do
    context "for a non encrypted device" do
      let(:device_name) { "/dev/sda2" }

      it "returns the device itself" do
        expect(device.plain_device).to eq device
      end
    end

    context "for an encrypted device" do
      let(:device_name) { "/dev/sda4" }

      it "returns the device itself" do
        expect(device.plain_device).to eq device
      end
    end

    context "for an encryption device" do
      let(:device_name) { "/dev/mapper/cr_sda4" }

      it "returns the encrypted device" do
        expect(device.plain_device).to_not eq device
        expect(device.plain_device.name).to eq "/dev/sda4"
      end
    end
  end

  describe "#lvm_pv" do
    context "for a device directly used as PV" do
      let(:device_name) { "/dev/sde2" }

      it "returns the LvmPv device" do
        expect(device.lvm_pv).to be_a Y2Storage::LvmPv
        expect(device.lvm_pv.blk_device).to eq device
      end
    end

    context "for a device used as encrypted PV" do
      let(:device_name) { "/dev/sde1" }

      it "returns the LvmPv device" do
        expect(device.lvm_pv).to be_a Y2Storage::LvmPv
        expect(device.lvm_pv.blk_device.is?(:encryption)).to eq true
        expect(device.lvm_pv.blk_device.plain_device).to eq device
      end
    end

    context "for a device that is not part of LVM" do
      let(:device_name) { "/dev/sda1" }

      it "returns nil" do
        expect(device.lvm_pv).to be_nil
      end
    end
  end

  describe "#direct_lvm_pv" do
    context "for a device directly used as PV" do
      let(:device_name) { "/dev/sde2" }

      it "returns the LvmPv device" do
        expect(device.direct_lvm_pv).to be_a Y2Storage::LvmPv
        expect(device.direct_lvm_pv.blk_device).to eq device
      end
    end

    context "for a device used as encrypted PV" do
      let(:device_name) { "/dev/sde1" }

      it "returns nil" do
        expect(device.direct_lvm_pv).to be_nil
      end
    end

    context "for a device that is not part of LVM" do
      let(:device_name) { "/dev/sda1" }

      it "returns nil" do
        expect(device.direct_lvm_pv).to be_nil
      end
    end
  end

  describe "#to_be_formatted?" do
    let(:new_devicegraph) { Y2Storage::StorageManager.instance.staging }
    let(:new_device) { Y2Storage::BlkDevice.find_by_name(new_devicegraph, device_name) }

    context "for the original device (same devicegraph)" do
      let(:device_name) { "/dev/sda1" }
      subject(:new_device) { device }

      it "returns false" do
        expect(new_device.to_be_formatted?(fake_devicegraph)).to eq false
      end
    end

    context "if the device is empty (not encrypted or used)" do
      context "if it didn't exist in the original devicegraph" do
        before do
          vg1 = Y2Storage::LvmVg.find_by_vg_name(new_devicegraph, "vg1")
          vg1.create_lvm_lv("newlv", 1.GiB)
        end

        let(:device_name) { "/dev/vg1/newlv" }

        it "returns false" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq false
        end
      end

      context "if it was empty in the original devicegraph" do
        let(:device_name) { "/dev/sdb" }

        it "returns false" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq false
        end
      end

      context "if it was not empty in the original devicegraph" do
        let(:device_name) { "/dev/sda1" }
        before { new_device.remove_descendants }

        it "returns false" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq false
        end
      end
    end

    context "if the device directly contains a filesystem" do
      context "if it didn't exist in the original devicegraph" do
        let(:device_name) { "/dev/vg1/newlv" }

        before do
          vg1 = Y2Storage::LvmVg.find_by_vg_name(new_devicegraph, "vg1")
          vg1.create_lvm_lv("newlv", 1.GiB)
          new_device.create_blk_filesystem(Y2Storage::Filesystems::Type::EXT4)
        end

        it "returns true" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq true
        end
      end

      context "if it contained a different filesystem in the original devicegraph" do
        let(:device_name) { "/dev/sda1" }
        before do
          new_device.remove_descendants
          new_device.create_blk_filesystem(Y2Storage::Filesystems::Type::EXT4)
        end

        it "returns true" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq true
        end
      end

      context "if it contained no filesystem in the original devicegraph" do
        let(:device_name) { "/dev/sdb" }
        before { new_device.create_blk_filesystem(Y2Storage::Filesystems::Type::EXT4) }

        it "returns true" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq true
        end
      end

      context "if it already contained that filesystem in the original devicegraph" do
        let(:device_name) { "/dev/sda1" }

        it "returns false" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq false
        end
      end
    end

    context "if the device contains an encrypted filesystem" do
      context "if it didn't exist in the original devicegraph" do
        let(:device_name) { "/dev/vg1/newlv" }

        before do
          vg1 = Y2Storage::LvmVg.find_by_vg_name(new_devicegraph, "vg1")
          vg1.create_lvm_lv("newlv", 1.GiB)
          new_enc = new_device.create_encryption("newenc")
          new_enc.create_blk_filesystem(Y2Storage::Filesystems::Type::EXT4)
        end

        it "returns true" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq true
        end
      end

      context "if it contained a different filesystem in the original devicegraph" do
        let(:device_name) { "/dev/sda4" }
        before do
          new_device.encryption.remove_descendants
          new_device.encryption.create_blk_filesystem(Y2Storage::Filesystems::Type::EXT4)
        end

        it "returns true" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq true
        end
      end

      context "if it contained no filesystem in the original devicegraph" do
        let(:device_name) { "/dev/sdb" }
        before do
          new_enc = new_device.create_encryption("newenc")
          new_enc.create_blk_filesystem(Y2Storage::Filesystems::Type::EXT4)
        end

        it "returns true" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq true
        end
      end

      context "if it already contained that filesystem in the original devicegraph" do
        let(:device_name) { "/dev/sda4" }

        it "returns false" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq false
        end
      end
    end

    context "if the device is used for other purpose (e.g. LVM PV)" do
      let(:vg1) { Y2Storage::LvmVg.find_by_vg_name(new_devicegraph, "vg1") }

      context "if it was empty in the original devicegraph" do
        let(:device_name) { "/dev/sdb" }

        before { vg1.add_lvm_pv(new_device) }

        it "returns false" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq false
        end
      end

      context "if it was not empty in the original devicegraph" do
        let(:device_name) { "/dev/sda1" }

        before do
          new_device.remove_descendants
          vg1.add_lvm_pv(new_device)
        end

        it "returns false" do
          expect(new_device.to_be_formatted?(fake_devicegraph)).to eq false
        end
      end
    end
  end

  describe "#basename" do
    let(:device_name) { "/dev/sda1" }

    it "returns the basename of the device's name" do
      expect(device.basename).to eq("sda1")
    end
  end

  describe "#udev_full_paths" do
    let(:device_name) { "/dev/sda1" }
    before { allow(device).to receive(:udev_paths).and_return(paths) }

    context "for devices with no known udev paths" do
      let(:paths) { [] }

      it "returns an empty array" do
        expect(device.udev_full_paths).to eq []
      end
    end

    context "for devices with several udev paths" do
      let(:paths) { ["pci-0000:00:1f.2-ata-1", "pci-0000:00:1f.2-scsi-0:0:0:0"] }

      it "returns an array" do
        expect(device.udev_full_paths).to be_an Array
      end

      it "prepends '/dev/disk/by-path' to every path" do
        expect(device.udev_full_paths).to contain_exactly(
          "/dev/disk/by-path/pci-0000:00:1f.2-ata-1",
          "/dev/disk/by-path/pci-0000:00:1f.2-scsi-0:0:0:0"
        )
      end
    end
  end

  describe "#udev_full_ids" do
    let(:device_name) { "/dev/sda1" }
    before { allow(device).to receive(:udev_ids).and_return(ids) }

    context "for devices with no known udev ids" do
      let(:ids) { [] }

      it "returns an empty array" do
        expect(device.udev_full_ids).to eq []
      end
    end

    context "for devices with several udev ids" do
      let(:ids) { ["ata-HGST_HTS725050A7E630_TF655AWHGATD2L", "wwn-0x5000cca77fc4e744"] }

      it "returns an array" do
        expect(device.udev_full_ids).to be_an Array
      end

      it "prepends '/dev/disk/by-id' to every id" do
        expect(device.udev_full_ids).to contain_exactly(
          "/dev/disk/by-id/ata-HGST_HTS725050A7E630_TF655AWHGATD2L",
          "/dev/disk/by-id/wwn-0x5000cca77fc4e744"
        )
      end
    end
  end

  describe "#udev_full_label" do
    let(:device_name) { "/dev/sda1" }
    before { allow(device).to receive(:blk_filesystem).and_return(filesystem) }

    context "for devices without filesystem" do
      let(:filesystem) { nil }

      it "returns nil" do
        expect(device.udev_full_label).to eq nil
      end
    end

    context "for devices without label" do
      let(:filesystem) { double(label: "") }

      it "returns nil" do
        expect(device.udev_full_label).to eq nil
      end
    end

    context "for devices with a label" do
      let(:filesystem) { double(label: "DATA") }

      it "returns an string" do
        expect(device.udev_full_label).to be_an String
      end

      it "prepends '/dev/disk/by-label' to the label" do
        expect(device.udev_full_label).to eq(
          "/dev/disk/by-label/DATA"
        )
      end
    end
  end

  describe "#udev_full_uuid" do
    let(:device_name) { "/dev/sda1" }
    before { allow(device).to receive(:blk_filesystem).and_return(filesystem) }

    context "for devices without filesystem" do
      let(:filesystem) { nil }

      it "returns nil" do
        expect(device.udev_full_uuid).to eq nil
      end
    end

    context "for devices without uuid" do
      let(:filesystem) { double(uuid: "") }

      it "returns nil" do
        expect(device.udev_full_uuid).to eq nil
      end
    end

    context "for devices with a uuid" do
      let(:filesystem) { double(uuid: "DATA") }

      it "returns an string" do
        expect(device.udev_full_uuid).to be_an String
      end

      it "prepends '/dev/disk/by-uuid' to the uuid" do
        expect(device.udev_full_uuid).to eq(
          "/dev/disk/by-uuid/DATA"
        )
      end
    end
  end

  describe "#udev_full_all" do
    let(:device_name) { "/dev/sda1" }
    before do
      allow(device).to receive(:blk_filesystem).and_return(double(label: "DATA", uuid: ""))
      allow(device).to receive(:udev_ids).and_return([])
      allow(device).to receive(:udev_paths).and_return(
        ["pci-0000:00:1f.2-ata-1", "pci-0000:00:1f.2-scsi-0:0:0:0"]
      )
    end

    it "returns array" do
      expect(device.udev_full_all).to be_an Array
    end

    it "does not contain any nil" do
      expect(device.udev_full_all).to_not include(nil)
    end

    it "contains all full udev links" do
      expect(device.udev_full_all).to contain_exactly(
        "/dev/disk/by-path/pci-0000:00:1f.2-ata-1",
        "/dev/disk/by-path/pci-0000:00:1f.2-scsi-0:0:0:0",
        "/dev/disk/by-label/DATA"
      )
    end
  end

  describe "#md" do
    before { fake_scenario("subvolumes-and-empty-md.xml") }

    context "for a device directly used in an MD array" do
      let(:device_name) { "/dev/sda4" }

      it "returns the Md device" do
        expect(device.md).to be_a Y2Storage::Md
        expect(device.md.devices).to include device
      end
    end

    context "for a device encrypted and used in an MD array" do
      let(:device_name) { "/dev/sda5" }

      it "returns the Md device" do
        expect(device.md).to be_a Y2Storage::Md
        expect(device.md.devices).to include device.encryption
      end
    end

    context "for a device that is not part of any MD array" do
      let(:device_name) { "/dev/sda3" }

      it "returns nil" do
        expect(device.md).to be_nil
      end
    end
  end

  describe "#direct_md" do
    before { fake_scenario("subvolumes-and-empty-md.xml") }

    context "for a device directly used in an MD array" do
      let(:device_name) { "/dev/sda4" }

      it "returns the Md device" do
        expect(device.direct_md).to be_a Y2Storage::Md
        expect(device.direct_md.devices).to include device
      end
    end

    context "for a device encrypted and used in an MD array" do
      let(:device_name) { "/dev/sda5" }

      it "returns nil" do
        expect(device.direct_md).to be_nil
      end
    end

    context "for a device that is not part of any MD array" do
      let(:device_name) { "/dev/sda3" }

      it "returns nil" do
        expect(device.direct_md).to be_nil
      end
    end
  end

  describe "#hwinfo" do
    let(:device_name) { "/dev/sda" }

    before do
      allow(Y2Storage::HWInfoReader.instance).to receive(:for_device)
        .with(device.name)
        .and_return(hwinfo)
    end

    context "when hardware info is available" do
      let(:hwinfo) { OpenStruct.new(driver_modules: ["ahci", "sd"]) }

      it "returns the hardware info" do
        expect(device.hwinfo).to eq(hwinfo)
      end
    end

    context "when hardware info is not available" do
      let(:hwinfo) { nil }

      it "returns nil" do
        expect(device.hwinfo).to eq(nil)
      end
    end
  end

  describe "#used?" do
    context "when the device is used as physical volume" do
      let(:scenario) { "empty_hard_disk_50GiB" }

      let(:device_name) { "/dev/sda" }

      before do
        vg = Y2Storage::LvmVg.create(fake_devicegraph, "vg0")
        vg.add_lvm_pv(device)
      end

      it "returns true" do
        expect(device.used?).to eq(true)
      end
    end

    context "when the device belongs to a MD RAID" do
      let(:scenario) { "mixed_disks" }

      let(:device_name) { "/dev/sda" }

      before do
        device.remove_descendants
        md = Y2Storage::Md.create(fake_devicegraph, "/dev/md0")
        md.add_device(device)
      end

      it "returns true" do
        expect(device.used?).to eq(true)
      end
    end

    context "when the device belongs to a DM RAID" do
      let(:scenario) { "md-imsm1-devicegraph.xml" }

      let(:device_name) { "/dev/sdc" }

      it "returns true" do
        expect(device.used?).to eq(true)
      end
    end

    context "when the device belongs to a Multipath" do
      let(:scenario) { "empty-dasd-and-multipath.xml" }

      let(:device_name) { "/dev/sda" }

      it "returns true" do
        expect(device.used?).to eq(true)
      end
    end

    context "when the device has a partition table" do
      let(:scenario) { "md_raid.xml" }

      let(:device_name) { "/dev/sda" }

      it "returns false" do
        expect(device.used?).to eq(false)
      end
    end

    context "when the device is formatted" do
      let(:scenario) { "empty_hard_disk_50GiB" }

      let(:device_name) { "/dev/sda" }

      before do
        device.create_filesystem(Y2Storage::Filesystems::Type::EXT3)
      end

      it "returns false" do
        expect(device.used?).to eq(false)
      end
    end

    context "when the device is empty" do
      let(:scenario) { "empty_hard_disk_50GiB" }

      let(:device_name) { "/dev/sda" }

      it "returns false" do
        expect(device.used?).to eq(false)
      end
    end
  end
end

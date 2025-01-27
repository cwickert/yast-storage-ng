# Copyright (c) [2016] SUSE LLC
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

require "storage"
require "y2storage/proposal/space_maker"
require "y2storage/proposal/partition_creator"
require "y2storage/proposal/lvm_helper"
require "y2storage/planned"

module Y2Storage
  module Proposal
    # Class to create devicegraphs that can accommodate a given collection of
    # volumes
    class DevicegraphGenerator
      include Yast::Logger

      attr_accessor :settings

      def initialize(settings)
        @settings = settings
      end

      # Devicegraph including all the specified volumes
      #
      # @param planned_devices [Array<Planned::Device>] devices to accommodate
      # @param initial_graph [Devicegraph] initial devicegraph
      #           (typically the representation of the current system)
      # @param space_maker [Proposal::SpaceMaker]
      #
      # @return [Devicegraph]
      # @raise [Error] if it was not possible to propose a devicegraph
      def devicegraph(planned_devices, initial_graph, space_maker)
        # We are going to alter the volumes in several ways, so let's be a
        # good citizen and do it in our own copy
        planned_devices = planned_devices.map(&:dup)

        lvm_lvs, part_devices = planned_devices.partition { |dev| dev.is_a?(Planned::LvmLv) }
        partitions = part_devices.map { |dev| planned_partition_for(dev) }

        lvm_helper = LvmHelper.new(lvm_lvs, settings)
        space_result = provide_space(partitions, initial_graph, lvm_helper, space_maker)

        refine_planned_partitions!(partitions, space_result[:deleted_partitions])
        creator_result = create_partitions(
          space_result[:partitions_distribution], space_result[:devicegraph]
        )
        reuse_partitions!(partitions, creator_result.devicegraph)

        graph = create_separate_vgs(planned_devices, creator_result).devicegraph

        if settings.use_lvm
          new_pvs = new_physical_volumes(space_result[:devicegraph], graph)
          graph = lvm_helper.create_volumes(graph, new_pvs)
        end

        graph.mount_points.each(&:adjust_mount_options)
        graph
      end

      protected

      # Planned partition that will hold the given planned device
      #
      # @param device [Planned::Device] a planned partition (so no transformation
      #   is required) or a planned VG (so a PV partition for the VG is calculated)
      # @return [Planned::Partition]
      def planned_partition_for(device)
        device.is_a?(Planned::Partition) ? device : device.single_pv_partition
      end

      # Creates the corresponding LVM devices for all the planned VGs in the
      # list of planned devices
      #
      # @param devices [Array<Planned::Device>] all planned devices
      # @param creator_result [Proposal::CreatorResult] result of the previous step,
      #     in which the partitions that must hold the PVs were created
      # @return [Proposal::CreatorResult]
      def create_separate_vgs(devices, creator_result)
        vgs = devices.select { |dev| dev.is_a?(Planned::LvmVg) }

        vgs.reduce(creator_result) do |result, vg|
          pvs = creator_result.created_names { |d| d.pv_for?(vg.volume_group_name) }
          creator = LvmCreator.new(result.devicegraph)
          result.merge(creator.create_volumes(vg, pvs))
        end
      end

      # Provides free disk space in the proposal devicegraph to fit the
      # planned partitions in.
      #
      # @raise [Error] if the goal is not reached
      #
      # @param planned_partitions [Array<Planned::Partition>] set partitions to
      #     make space for.
      # @param space_maker [SpaceMaker]
      #
      # @return [Devicegraph]
      def provide_space(planned_partitions, devicegraph, lvm_helper, space_maker)
        if settings.use_lvm
          provide_space_lvm(planned_partitions, devicegraph, lvm_helper, space_maker)
        else
          provide_space_no_lvm(planned_partitions, devicegraph, lvm_helper, space_maker)
        end
      end

      # Variant of #provide_space when LVM is not involved
      # @see #provide_space
      def provide_space_no_lvm(planned_partitions, devicegraph, lvm_helper, space_maker)
        result = space_maker.provide_space(devicegraph, planned_partitions, lvm_helper)
        log.info "Found enough space"
        result
      end

      # Variant of #provide_space when LVM is involved. It first tries to reuse
      # the existing volume groups (one at a time). If that fails, it tries to
      # create a new volume group from scratch.
      #
      # @see #provide_space
      def provide_space_lvm(planned_partitions, devicegraph, lvm_helper, space_maker)
        lvm_helper.reused_volume_group = nil

        lvm_helper.reusable_volume_groups(devicegraph).each do |vg|

          lvm_helper.reused_volume_group = vg
          result = space_maker.provide_space(devicegraph, planned_partitions, lvm_helper)
          log.info "Found enough space including LVM, reusing #{vg}"
          return result
        rescue Error
          next

        end

        lvm_helper.reused_volume_group = nil
        result = space_maker.provide_space(devicegraph, planned_partitions, lvm_helper)
        log.info "Found enough space including LVM"

        result
      end

      # List of unused partitions with LVM id (i.e. potential physical volumes) that
      # are present in the new devicegraph but were not there in the old one.
      #
      # @param old_devicegraph [Devicegraph]
      # @param new_devicegraph [Devicegraph]
      # @return [Array<String>] device names of the partitions
      def new_physical_volumes(old_devicegraph, new_devicegraph)
        all_pvs = new_devicegraph.partitions.select do |part|
          part.id.is?(:lvm) && !part.part_of_lvm_or_md?
        end
        old_pv_sids = old_devicegraph.partitions.select { |p| p.id.is?(:lvm) }.map(&:sid)
        all_pvs.reject { |pv| old_pv_sids.include?(pv.sid) }.map(&:name)
      end

      # Adds some extra information to the planned partitions inferred from
      # the list of partitions deleted by the space maker.
      #
      # It enforces reuse of UUIDs and labels from the deleted swap
      # partitions.
      #
      # It modifies the passed volumes.
      #
      # @param planned_partitions [Array<Planned::Partition>] planned
      #     partitions to modify
      # @param deleted_partitions [Array<Partition>] partitions
      #     deleted from the initial devicegraph
      def refine_planned_partitions!(planned_partitions, deleted_partitions)
        deleted_swaps = deleted_partitions.select do |part|
          part.id.is?(:swap) && part.formatted_as?(:swap)
        end
        new_swap_volumes = planned_partitions.select do |vol|
          !vol.reuse_name && vol.mount_point == "swap"
        end

        new_swap_volumes.each_with_index do |swap_volume, idx|
          deleted_swap = deleted_swaps[idx]
          break unless deleted_swap

          swap_volume.uuid = deleted_swap.filesystem.uuid
          swap_volume.label = deleted_swap.filesystem.label
        end
      end

      # Creates partitions representing a set of volumes
      #
      # @param distribution [Planned::PartitionsDistribution]
      # @param initial_graph [Devicegraph] initial devicegraph
      #
      # @return [Proposal::CreatorResult]
      def create_partitions(distribution, initial_graph)
        partition_creator = PartitionCreator.new(initial_graph)
        partition_creator.create_partitions(distribution)
      end

      # Adjusts pre-existing (not created by us) partitions assigning its
      # mount point and boot flag
      #
      # It works directly on the passed devicegraph
      #
      # @param planned_partitions [Array<Planned::Partition>]
      # @param graph [Devicegraph] devicegraph to modify
      def reuse_partitions!(planned_partitions, graph)
        planned_partitions.each do |planned|
          planned.reuse!(graph)
        end
      end
    end
  end
end

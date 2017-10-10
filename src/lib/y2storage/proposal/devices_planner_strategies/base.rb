# encoding: utf-8

# Copyright (c) [2016-2017] SUSE LLC
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

require "y2storage/planned"
require "y2storage/disk_size"
require "y2storage/boot_requirements_checker"
require "y2storage/exceptions"
require "abstract_method"

module Y2Storage
  module Proposal
    module DevicesPlannerStrategies
      # Abstract base class with common functionalty for different devices
      # planner strategies.
      class Base
        include Yast::Logger

        attr_accessor :settings

        def initialize(settings, devicegraph)
          @settings = settings
          @devicegraph = devicegraph
        end

        # @!method planned_devices
        #   List of devices (read: partitions or volumes) that need to be
        #   created to satisfy the settings.
        #
        #   @note This method must be reimplemented by derived classes.
        #
        #   @see DevicesPlanner#planned_devices
        #
        #   @param target [Symbol] :desired, :min
        #   @return [Array<Planned::Device>]
        abstract_method :planned_devices

      protected

        # @return [Devicegraph]
        attr_reader :devicegraph

        # @return [Symbol] :desired or :min
        attr_reader :target

        # Planned devices needed by the bootloader
        #
        # @return [Array<Planned::Device>]
        def planned_boot_devices(planned_devices)
          checker = BootRequirementsChecker.new(
            devicegraph, planned_devices: planned_devices, boot_disk_name: settings.root_device
          )
          checker.needed_partitions(target)
        rescue BootRequirementsChecker::Error => error
          # As documented, {BootRequirementsChecker#needed_partition} raises this
          # exception if it's impossible to get a bootable system, even adding
          # more partitions.
          raise NotBootableError, error.message
        end

        # Swap partition that can be reused.
        #
        # It returns the smaller partition that is big enough for our purposes.
        #
        # @return [Partition]
        def reusable_swap(required_size)
          return nil if settings.use_lvm || settings.use_encryption

          partitions = devicegraph.disk_devices.map(&:swap_partitions).flatten
          partitions.select! { |part| part.size >= required_size }
          # Use #name in case of #size tie to provide stable sorting
          partitions.sort_by { |part| [part.size, part.name] }.first
        end

        # Delete shadowed subvolumes from each planned device
        def remove_shadowed_subvolumes(planned_devices)
          planned_devices.each do |device|
            next unless device.respond_to?(:subvolumes)

            device.shadowed_subvolumes(planned_devices).each do |subvolume|
              log.info "Subvolume #{subvolume} would be shadowed. Removing it."
              device.subvolumes.delete(subvolume)
            end
          end
        end

        # Return the total amount of RAM as DiskSize
        #
        # @return [DiskSize] current RAM size
        def ram_size
          # FIXME: use the .proc.meminfo agent and its MemTotal field
          #   mem_info_map = Convert.to_map(SCR.Read(path(".proc.meminfo")))
          # See old Partitions.rb: SwapSizeMb()
          DiskSize.GiB(8)
        end
      end
    end
  end
end

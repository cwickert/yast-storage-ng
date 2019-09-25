# Copyright (c) [2019] SUSE LLC
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

require "y2storage/encryption_processes/swap"

module Y2Storage
  module EncryptionProcesses
    # Encryption swap process (see {Swap}) for z Systems to encrypt a device by using protected keys
    class ProtectedSwap < Swap
      KEY_FILE = "/sys/devices/virtual/misc/pkey/protkey/protkey_aes_256_xts".freeze
      private_constant :KEY_FILE

      CIPHER = "paes-xts-plain64".freeze
      private_constant :CIPHER

      KEY_SIZE = "1280".freeze
      private_constant :KEY_SIZE

      class << self
        # @see Swap.key_file
        def key_file
          KEY_FILE
        end

        # @see Swap.cipher
        def cipher
          CIPHER
        end

        # @see Swap.key_size
        def key_size
          KEY_SIZE
        end
      end
    end
  end
end


require "yast"
require "storage"
require "storage/storage-manager"
require "storage/extensions"
require "expert-partitioner/views/view"

Yast.import "UI"

include Yast::I18n


module ExpertPartitioner

  class FilesystemView < View

    FIELDS = [ :sid, :icon, :filesystem, :mountpoint, :mount_by, :label ]

    def create
      Table(Id(:table), Storage::Device.table_header(FIELDS), items)
    end

    def items

      storage = Yast::Storage::StorageManager.instance
      staging = storage.staging()

      filesystems = Storage::Filesystem::all(staging)

      return filesystems.to_a.map do |filesystem|
        filesystem.table_row(FIELDS)
      end

    end

  end

end

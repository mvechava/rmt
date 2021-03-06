require 'rails_helper'

# rubocop:disable RSpec/NestedGroups

RSpec.describe RMT::Mirror do
  describe '#mirror' do
    around do |example|
      @tmp_dir = Dir.mktmpdir('rmt')
      example.run
      FileUtils.remove_entry(@tmp_dir)
    end

    context 'without auth_token' do
      let(:rmt_mirror) do
        described_class.new(
          mirroring_base_dir: @tmp_dir,
          repository_url: 'http://localhost/dummy_repo/',
          local_path: '/dummy_repo',
          mirror_src: false
        )
      end

      before do
        VCR.use_cassette 'mirroring' do
          rmt_mirror.mirror
        end
      end

      it 'downloads rpm files' do
        rpm_entries = Dir.entries(File.join(@tmp_dir, 'dummy_repo')).select { |entry| entry =~ /\.rpm$/ }
        expect(rpm_entries.length).to eq(4)
      end

      it 'downloads drpm files' do
        rpm_entries = Dir.entries(File.join(@tmp_dir, 'dummy_repo')).select { |entry| entry =~ /\.drpm$/ }
        expect(rpm_entries.length).to eq(2)
      end
    end

    context 'with auth_token' do
      let(:rmt_mirror) do
        described_class.new(
          mirroring_base_dir: @tmp_dir,
          repository_url: 'http://localhost/dummy_repo/',
          local_path: '/dummy_repo',
          auth_token: 'repo_auth_token',
          mirror_src: false
        )
      end

      before do
        VCR.use_cassette 'mirroring_with_auth_token' do
          rmt_mirror.mirror
        end
      end

      it 'downloads rpm files' do
        rpm_entries = Dir.entries(File.join(@tmp_dir, 'dummy_repo')).select { |entry| entry =~ /\.rpm$/ }
        expect(rpm_entries.length).to eq(4)
      end

      it 'downloads drpm files' do
        rpm_entries = Dir.entries(File.join(@tmp_dir, 'dummy_repo')).select { |entry| entry =~ /\.drpm$/ }
        expect(rpm_entries.length).to eq(2)
      end
    end

    context 'product with license and signatures' do
      let(:rmt_mirror) do
        described_class.new(
          mirroring_base_dir: @tmp_dir,
          repository_url: 'http://localhost/dummy_product/product/',
          local_path: '/dummy_product/product/',
          auth_token: 'repo_auth_token',
          mirror_src: false
        )
      end

      before do
        VCR.use_cassette 'mirroring_product' do
          rmt_mirror.mirror
        end
      end

      it 'downloads rpm files' do
        rpm_entries = Dir.entries(File.join(@tmp_dir, 'dummy_product/product/')).select { |entry| entry =~ /\.rpm$/ }
        expect(rpm_entries.length).to eq(4)
      end

      it 'downloads drpm files' do
        rpm_entries = Dir.entries(File.join(@tmp_dir, 'dummy_product/product/')).select { |entry| entry =~ /\.drpm$/ }
        expect(rpm_entries.length).to eq(2)
      end

      it 'downloads repomd.xml signatures' do
        ['repomd.xml.key', 'repomd.xml.asc'].each do |file|
          expect(File.size(File.join(@tmp_dir, 'dummy_product/product/repodata/', file))).to be > 0
        end
      end

      it 'downloads product license' do
        ['directory.yast', 'license.txt', 'license.de.txt', 'license.ru.txt'].each do |file|
          expect(File.size(File.join(@tmp_dir, 'dummy_product/product.license/', file))).to be > 0
        end
      end
    end

    context 'handles erroring' do
      let(:mirroring_dir) { @tmp_dir }
      let(:rmt_mirror) do
        described_class.new(
          mirroring_base_dir: mirroring_dir,
          repository_url: 'http://localhost/dummy_product/product/',
          local_path: '/dummy_product/product/',
          auth_token: 'repo_auth_token',
          mirror_src: false
        )
      end

      context 'when mirroring_base_dir is not writable' do
        let(:mirroring_dir) { '/non/existent/path' }

        it 'raises exception' do
          VCR.use_cassette 'mirroring_product' do
            expect { rmt_mirror.mirror }.to raise_error(RMT::Mirror::Exception)
          end
        end
      end

      context "when can't create tmp dir" do
        before { allow(Dir).to receive(:mktmpdir).and_raise('mktmpdir exception') }
        it 'handles the exception' do
          VCR.use_cassette 'mirroring_product' do
            expect { rmt_mirror.mirror }.to raise_error(RMT::Mirror::Exception)
          end
        end
      end

      context "when can't download metadata" do
        before { allow_any_instance_of(RMT::Downloader).to receive(:download).and_raise(RMT::Downloader::Exception) }
        it 'handles RMT::Downloader::Exception' do
          VCR.use_cassette 'mirroring_product' do
            expect { rmt_mirror.mirror }.to raise_error(RMT::Mirror::Exception)
          end
        end
      end

      context "when can't download some of the license files" do
        before do
          allow_any_instance_of(RMT::Downloader).to receive(:download).and_wrap_original do |klass, *args|
            raise RMT::Downloader::Exception.new unless args[0] == 'directory.yast'
            klass.call(*args)
          end
        end
        it 'handles RMT::Downloader::Exception' do
          VCR.use_cassette 'mirroring_product' do
            expect { rmt_mirror.mirror }.to raise_error(RMT::Mirror::Exception, /Error during mirroring metadata:/)
          end
        end
      end

      context "when can't parse metadata" do
        before { allow_any_instance_of(RMT::Rpm::RepomdXmlParser).to receive(:parse).and_raise('Parse error') }
        it 'removes the temporary metadata directory' do
          VCR.use_cassette 'mirroring_product' do
            expect { rmt_mirror.mirror }.to raise_error(RMT::Mirror::Exception)
            expect(File.exist?(rmt_mirror.instance_variable_get(:@temp_metadata_dir))).to be(false)
          end
        end
      end

      context 'when Interrupt is raised' do
        before { allow_any_instance_of(RMT::Rpm::RepomdXmlParser).to receive(:parse).and_raise(Interrupt.new) }
        it 'removes the temporary metadata directory' do
          VCR.use_cassette 'mirroring_product' do
            expect { rmt_mirror.mirror }.to raise_error(Interrupt)
            expect(File.exist?(rmt_mirror.instance_variable_get(:@temp_metadata_dir))).to be(false)
          end
        end
      end
    end

    context 'deduplication' do
      let(:rmt_source_mirror) do
        described_class.new(
          mirroring_base_dir: @tmp_dir,
          repository_url: 'http://localhost/dummy_product/product/',
          local_path: '/dummy_product/product/',
          auth_token: 'repo_auth_token',
          mirror_src: false
        )
      end
      let(:rmt_dedup_mirror) do
        described_class.new(
          mirroring_base_dir: @tmp_dir,
          repository_url: 'http://localhost/dummy_deduped_product/product/',
          local_path: '/dummy_deduped_product/product/',
          auth_token: 'repo_auth_token',
          mirror_src: false
        )
      end
      let(:dedup_path) { File.join(@tmp_dir, 'dummy_deduped_product/product/') }
      let(:source_path) { File.join(@tmp_dir, 'dummy_product/product/') }

      shared_examples_for 'a deduplicated run' do |source_nlink, dedup_nlink, has_same_content|
        it 'downloads source rpm files' do
          rpm_entries = Dir.entries(File.join(source_path)).select { |entry| entry =~ /\.rpm$/ }
          expect(rpm_entries.length).to eq(4)
        end

        it 'deduplicates rpm files' do
          rpm_entries = Dir.entries(File.join(dedup_path)).select { |entry| entry =~ /\.rpm$/ }
          expect(rpm_entries.length).to eq(4)
        end


        it 'has correct content for deduplicated rpm files' do
          Dir.entries(File.join(dedup_path)).select { |entry| entry =~ /\.rpm$/ }.each do |file|
            if has_same_content
              expect(File.read(dedup_path + file)).to eq(File.read(source_path + file))
            else
              expect(File.read(dedup_path + file)).not_to eq(File.read(source_path + file))
            end
          end
        end

        it "source rpms have #{source_nlink} nlink" do
          Dir.entries(source_path).select { |entry| entry =~ /\.rpm$/ }.each do |file|
            expect(File.stat(source_path + file).nlink).to eq(source_nlink)
          end
        end

        it "dedup rpms have #{dedup_nlink} nlink" do
          Dir.entries(dedup_path).select { |entry| entry =~ /\.rpm$/ }.each do |file|
            expect(File.stat(dedup_path + file).nlink).to eq(dedup_nlink)
          end
        end

        it 'downloads source drpm files' do
          rpm_entries = Dir.entries(File.join(source_path)).select { |entry| entry =~ /\.drpm$/ }
          expect(rpm_entries.length).to eq(2)
        end

        it 'deduplicates drpm files' do
          rpm_entries = Dir.entries(File.join(dedup_path)).select { |entry| entry =~ /\.drpm$/ }
          expect(rpm_entries.length).to eq(2)
        end

        it 'has correct content for deduplicated drpm files' do
          Dir.entries(File.join(dedup_path)).select { |entry| entry =~ /\.drpm$/ }.each do |file|
            if has_same_content
              expect(File.read(dedup_path + file)).to eq(File.read(source_path + file))
            else
              expect(File.read(dedup_path + file)).not_to eq(File.read(source_path + file))
            end
          end
        end

        it "source drpms have #{source_nlink} nlink" do
          Dir.entries(source_path).select { |entry| entry =~ /\.drpm$/ }.each do |file|
            expect(File.stat(source_path + file).nlink).to eq(source_nlink)
          end
        end

        it "dedup drpms have #{dedup_nlink} nlink" do
          Dir.entries(dedup_path).select { |entry| entry =~ /\.drpm$/ }.each do |file|
            expect(File.stat(dedup_path + file).nlink).to eq(dedup_nlink)
          end
        end
      end

      context 'by copy' do
        before do
          deduplication_method(:copy)
          VCR.use_cassette 'mirroring_product_with_dedup' do
            rmt_source_mirror.mirror
            rmt_dedup_mirror.mirror
          end
        end

        it_behaves_like 'a deduplicated run', 1, 1, true
      end

      context 'by hardlink' do
        before do
          deduplication_method(:hardlink)
          VCR.use_cassette 'mirroring_product_with_dedup' do
            rmt_source_mirror.mirror
            rmt_dedup_mirror.mirror
          end
        end

        it_behaves_like 'a deduplicated run', 2, 2, true
      end

      context 'by copy with corruption' do
        before do
          deduplication_method(:copy)
          VCR.use_cassette 'mirroring_product_with_dedup' do
            rmt_source_mirror.mirror
            Dir.entries(source_path).select { |entry| entry =~ /(\.drpm|\.rpm)$/ }.each do |filename|
              File.open(source_path + filename, 'w') { |f| f.write('corruption') }
            end
            rmt_dedup_mirror.mirror
          end
        end

        it_behaves_like 'a deduplicated run', 1, 1, false
      end
    end

    context 'with cached metadata' do
      let(:mirroring_dir) do
        FileUtils.cp_r(file_fixture('dummy_product'), File.join(@tmp_dir, 'dummy_product'))
        @tmp_dir
      end
      let(:rmt_mirror) do
        described_class.new(
          mirroring_base_dir: mirroring_dir,
          repository_url: 'http://localhost/dummy_product/product/',
          local_path: '/dummy_product/product/',
          auth_token: 'repo_auth_token',
          mirror_src: false
        )
      end

      before do
        allow_any_instance_of(RMT::Downloader).to receive(:get_cache_timestamp) { 'Mon, 01 Jan 2018 10:10:00 GMT' }

        VCR.use_cassette 'mirroring_product_with_cached_metadata' do
          rmt_mirror.mirror
        end
      end

      it 'downloads rpm files' do
        rpm_entries = Dir.entries(File.join(@tmp_dir, 'dummy_product/product/')).select { |entry| entry =~ /\.rpm$/ }
        expect(rpm_entries.length).to eq(4)
      end
    end
  end
end

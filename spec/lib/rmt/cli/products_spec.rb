require 'rails_helper'

# rubocop:disable RSpec/NestedGroups

RSpec.describe RMT::CLI::Products do
  describe 'list-command' do
    subject(:command) { described_class.start(argv) }

    let(:argv) { ['list'] }

    it 'mentions --all option' do
      expect { described_class.start(argv) }.to output(
        "Only enabled products are shown by default. Use the `--all` option to see all products.\n"
      ).to_stdout.and output(/No matching products found/).to_stderr
    end

    context 'with empty database' do
      context 'with no options' do
        it 'warns about no matches' do
          expect { described_class.start(argv) }.to output(
            "No matching products found in the database.\n"
          ).to_stderr.and output(/Only enabled products are shown/).to_stdout
        end
      end

      context 'with --all option' do
        let(:argv) { ['list', '--all'] }

        it 'warns about running sync command first' do
          expect { described_class.start(argv) }.to output(
            "Run \"rmt-cli sync\" to synchronize with your SUSE Customer Center data first.\n"
          ).to_stderr
        end

        it 'does not mention --all option' do
          expect { described_class.start(argv) }.to output('').to_stdout.and output(/rmt-cli sync/).to_stderr
        end
      end
    end

    context 'with products in database' do
      let!(:disabled_product) { create :product } # rubocop:disable RSpec/LetSetup
      let!(:enabled_product) { create :product, :with_mirrored_repositories }
      let!(:beta_product) { create :product, release_stage: 'beta' }

      let(:expected_output) do
        Terminal::Table.new(
          headings: ['ID', 'Name', 'Version', 'Architecture', 'Product string', 'Release stage', 'Mirror?', 'Last mirrored'],
          rows: expected_rows
        ).to_s + "\n"
      end

      context 'with no options' do
        let(:expected_rows) do
          [[
            enabled_product.id,
            enabled_product.name,
            enabled_product.version,
            enabled_product.arch,
            enabled_product.product_string,
            enabled_product.release_stage,
            enabled_product.mirror?,
            enabled_product.last_mirrored_at
          ]]
        end

        it 'lists only enabled products' do
          expect { described_class.start(argv) }.to output(/.*#{expected_output}.*/).to_stdout.and output('').to_stderr
        end
      end

      context 'with --all option' do
        let(:argv) { ['list', '--all'] }
        let(:expected_rows) do
          Product.all.map do |product|
            [
              product.id,
              product.name,
              product.version,
              product.arch,
              product.product_string,
              product.release_stage,
              product.mirror?,
              product.last_mirrored_at
            ]
          end
        end

        it 'lists all products' do
          expect { described_class.start(argv) }.to output(/.*#{expected_output}.*/).to_stdout.and output('').to_stderr
        end
      end

      context 'with --release-stage option' do
        let(:argv) { ['list', '--all', '--release-stage', 'released'] }
        let(:expected_rows) do
          [[
            beta_product.id,
            beta_product.name,
            beta_product.version,
            beta_product.arch,
            beta_product.product_string,
            beta_product.release_stage,
            beta_product.mirror?,
            beta_product.last_mirrored_at
          ]]
        end

        it 'lists only products in that release stage' do
          expect { described_class.start(argv) }.to output(/.*#{expected_output}.*/).to_stdout.and output('').to_stderr
        end
      end
    end
  end

  describe '#enable' do
    let(:product) { create :product, :with_not_mirrored_repositories }

    context 'by product ID' do
      let(:argv) { ['enable', product.id.to_s] }
      let(:expected_output) { "#{product.repositories.where(enabled: true).count} repo(s) successfully enabled.\n" }

      before { expect { described_class.start(argv) }.to output(expected_output).to_stdout.and output('').to_stderr }

      it 'enables the mandatory product repositories' do
        product.repositories.each do |repository|
          expect(repository.mirroring_enabled).to eq(repository.enabled)
        end
      end
    end

    context 'by wrong product ID' do
      let(:false_id) { (product.id + 1).to_s }
      let(:argv) { ['enable', false_id] }
      let(:expected_output) { "Product by id \"#{false_id}\" not found.\n" }

      before do
        expect(described_class).to receive(:exit)
        expect { described_class.start(argv) }.to output(expected_output).to_stderr.and output('').to_stdout
      end

      it 'enables the mandatory product repositories' do
        product.repositories.each do |repository|
          expect(repository.mirroring_enabled).to eq(false)
        end
      end
    end

    context 'by product string' do
      let(:argv) { ['enable', product.product_string] }
      let(:expected_output) { "#{product.repositories.where(enabled: true).count} repo(s) successfully enabled.\n" }

      before { expect { described_class.start(argv) }.to output(expected_output).to_stdout.and output('').to_stderr }

      it 'enables the mandatory product repositories' do
        product.repositories.each do |repository|
          expect(repository.mirroring_enabled).to eq(repository.enabled)
        end
      end
    end
  end

  describe '#disable' do
    let(:product) { create :product, :with_mirrored_repositories }
    let(:expected_output) { "#{product.repositories.count} repo(s) successfully disabled.\n" }

    before do
      expect { described_class.start(argv) }.to output(expected_output).to_stdout.and output('').to_stderr
    end

    context 'by product ID' do
      let(:argv) { ['disable', product.id.to_s] }

      it 'disabled the mandatory product repositories' do
        product.repositories.each do |repository|
          expect(repository.mirroring_enabled).to eq(false)
        end
      end
    end

    context 'by product string' do
      let(:argv) { ['disable', product.product_string] }

      it 'disabled the mandatory product repositories' do
        product.repositories.each do |repository|
          expect(repository.mirroring_enabled).to eq(false)
        end
      end
    end
  end
end

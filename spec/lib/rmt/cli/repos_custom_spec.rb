require 'rails_helper'

# rubocop:disable RSpec/MultipleExpectations

describe RMT::CLI::ReposCustom do
  subject(:command) { described_class.start(argv) }

  let(:product) { create :product }
  let(:external_url) { 'http://example.com/repos' }
  let(:repository_service) { RepositoryService.new }

  describe '#add' do
    context 'product exists' do
      let(:argv) { ['add', external_url, 'foo'] }

      it 'adds the repository to the database' do
        expect { described_class.start(argv) }.to output("Successfully added custom repository.\n").to_stdout.and output('').to_stderr
        expect(Repository.find_by(name: 'foo')).not_to be_nil
      end
    end

    context 'invalid URL' do
      let(:argv) { %w[add http://foo.bar foo] }

      it 'adds the repository to the database' do
        expect { described_class.start(argv) }.to output("Invalid URL \"http://foo.bar\" provided.\n").to_stderr.and output('').to_stdout
        expect(Repository.find_by(name: 'foo')).to be_nil
      end
    end

    context 'duplicate URL' do
      let(:argv) { ['add', external_url, 'foo'] }

      it 'does not update previous repository if non-custom' do
        expect do
          create :repository, external_url: external_url, name: 'foobar'
          described_class.start(argv)
        end.to output("A repository by this URL already exists.\n").to_stderr.and output('').to_stdout
        expect(Repository.find_by(external_url: external_url).name).to eq('foobar')
      end

      it 'does not update previous repository if custom' do
        expect do
          create :repository, :custom, external_url: external_url, name: 'foobar'
          described_class.start(argv)
        end.to output("A repository by this URL already exists.\n").to_stderr.and output('').to_stdout
        expect(Repository.find_by(external_url: external_url).name).to eq('foobar')
      end
    end
  end

  describe '#list' do
    shared_context 'rmt-cli custom repos list' do |command|
      let(:argv) { [command] }

      context 'empty repository list' do
        it 'says that there are not any custom repositories' do
          expect { described_class.start(argv) }.to output("No custom repositories found.\n").to_stderr
        end
      end

      context 'with custom repository' do
        let(:custom_repository) { create :repository, :custom, name: 'custom foo' }

        it 'displays the custom repo' do
          expect { described_class.start(argv) }.to output(/.*#{custom_repository.name}.*/).to_stdout
        end
      end
    end

    it_behaves_like 'rmt-cli custom repos list', 'list'
    it_behaves_like 'rmt-cli custom repos list', 'ls'
  end

  describe '#enable' do
    subject(:repository) { create :repository, :custom, :with_products }

    let(:command) do
      repository
      described_class.start(argv)
      repository.reload
    end

    context 'without parameters' do
      let(:argv) { ['enable'] }

      before { expect { command }.to output(/Usage:/).to_stderr }

      its(:mirroring_enabled) { is_expected.to be(false) }
    end

    context 'repo id does not exist' do
      let(:argv) { ['enable', (repository.id + 1).to_s] }

      before { expect { command }.to output("Repository not found. No repositories were modified.\n").to_stderr.and output('').to_stdout }

      its(:mirroring_enabled) { is_expected.to be(false) }
    end

    context 'by repo id' do
      let(:argv) { ['enable', repository.id.to_s] }

      before { expect { command }.to output("Repository successfully enabled.\n").to_stdout }

      its(:mirroring_enabled) { is_expected.to be(true) }
    end
  end

  describe '#disable' do
    subject(:repository) { create :repository, :custom, :with_products, mirroring_enabled: true }

    let(:command) do
      repository
      described_class.start(argv)
      repository.reload
    end

    context 'without parameters' do
      let(:argv) { ['disable'] }

      before { expect { command }.to output(/Usage:/).to_stderr }

      its(:mirroring_enabled) { is_expected.to be(true) }
    end

    context 'repo id does not exist' do
      let(:argv) { ['disable', (repository.id + 1).to_s] }

      before { expect { command }.to output("Repository not found. No repositories were modified.\n").to_stderr.and output('').to_stdout }

      its(:mirroring_enabled) { is_expected.to be(true) }
    end

    context 'by repo id' do
      let(:argv) { ['disable', repository.id.to_s] }

      before { expect { command }.to output("Repository successfully disabled.\n").to_stdout }

      its(:mirroring_enabled) { is_expected.to be(false) }
    end
  end

  describe '#remove' do
    shared_context 'rmt-cli custom repos remove' do |command|
      let(:suse_repository) { create :repository, name: 'awesome-rmt-repo' }
      let(:custom_repository) { create :repository, :custom, name: 'custom foo' }

      context 'not found' do
        let(:argv) { [command, 'totally_wrong'] }

        before do
          expect { described_class.start(argv) }.to output("Cannot find custom repository by id \"totally_wrong\".\n").to_stderr
        end
        it 'does not delete suse repository' do
          expect(Repository.find_by(id: suse_repository.id)).not_to be_nil
        end

        it 'does not delete custom repository' do
          expect(Repository.find_by(id: custom_repository.id)).not_to be_nil
        end
      end

      context 'non-custom repository' do
        let(:argv) { [command, suse_repository.id] }

        before do
          expect { described_class.start(argv) }.to output("Cannot find custom repository by id \"#{suse_repository.id}\".\n").to_stderr
        end

        it 'does not delete suse non-custom repository' do
          expect(Repository.find_by(id: suse_repository.id)).not_to be_nil
        end
      end

      context 'custom repository' do
        let(:argv) { [command, custom_repository.id] }

        before do
          expect { described_class.start(argv) }.to output("Removed custom repository by id \"#{custom_repository.id}\".\n").to_stdout
        end

        it 'deletes custom repository' do
          expect(Repository.find_by(id: custom_repository.id)).to be_nil
        end
      end
    end

    it_behaves_like 'rmt-cli custom repos remove', 'remove'
    it_behaves_like 'rmt-cli custom repos remove', 'rm'
  end

  describe '#attach' do
    context 'repository does not exist' do
      let(:argv) { ['attach', 'foo', product.id] }

      it 'fails' do
        expect { described_class.start(argv) }.to output("Cannot find custom repository by id \"foo\".\n").to_stderr.and output('').to_stdout
      end
    end

    context 'repository is from scc' do
      let(:repository) { create :repository }
      let(:argv) { ['attach', repository.id, product.id] }

      it('does not have an attached product') { expect(repository.products.count).to eq(0) }

      it 'fails' do
        expect { described_class.start(argv) }.to output("Cannot find custom repository by id \"#{repository.id}\".\n").to_stderr.and output('').to_stdout
        expect(repository.products.count).to eq(0)
      end
    end

    context 'product does not exist' do
      let(:repository) { create :repository, :custom }
      let(:argv) { ['attach', repository.id, 'foo'] }

      it('does not have an attached product') { expect(repository.products.count).to eq(0) }

      it 'fails' do
        expect { described_class.start(argv) }.to output("Cannot find product by id \"foo\".\n").to_stderr.and output('').to_stdout
        expect(repository.products.count).to eq(0)
      end
    end

    context 'product and repo exist' do
      let(:repository) { create :repository, :custom }
      let(:argv) { ['attach', repository.id, product.id] }

      it('does not have an attached product') { expect(repository.products.count).to eq(0) }

      it 'attaches the repository to the product' do
        expect { described_class.start(argv) }.to output('').to_stderr.and output("Attached repository to product\n").to_stdout
        expect(repository.products.first.id).to eq(product.id)
      end
    end
  end

  describe '#detach' do
    context 'repository does not exist' do
      let(:argv) { ['detach', 'foo', product.id] }

      it 'fails' do
        expect { described_class.start(argv) }.to output("Cannot find custom repository by id \"foo\".\n").to_stderr.and output('').to_stdout
      end
    end

    context 'repository is from scc' do
      let(:repository) { create :repository }
      let(:argv) { ['detach', 'foo', repository.id] }

      before do
        repository_service.attach_product!(product, repository)
      end

      it('has an attached product') { expect(repository.products.count).to eq(1) }

      it 'fails' do
        expect { described_class.start(argv) }.to output("Cannot find custom repository by id \"foo\".\n").to_stderr.and output('').to_stdout
        expect(repository.products.count).to eq(1)
      end
    end

    context 'product does not exist' do
      let(:repository) { create :repository, :custom }
      let(:argv) { ['detach', repository.id, 'foo'] }

      before do
        repository_service.attach_product!(product, repository)
      end

      it('has an attached product') { expect(repository.products.count).to eq(1) }

      it 'fails' do
        expect { described_class.start(argv) }.to output("Cannot find product by id \"foo\".\n").to_stderr.and output('').to_stdout
        expect(repository.products.count).to eq(1)
      end
    end

    context 'product and repo exist' do
      let(:repository) { create :repository, :custom }
      let(:argv) { ['detach', repository.id, product.id] }

      before do
        repository_service.attach_product!(product, repository)
      end

      it('has an attached product') { expect(repository.products.count).to eq(1) }

      it 'detaches the repository from the product' do
        expect { described_class.start(argv) }.to output('').to_stderr.and output("Detached repository from product\n").to_stdout
        expect(repository.products.count).to eq(0)
      end
    end
  end

  describe '#products' do
    context 'scc repository' do
      let(:repository) { create :repository }
      let(:argv) { ['product', repository.id] }

      before do
        repository_service.attach_product!(product, repository)
      end

      it('has an attached product') { expect(repository.products.count).to eq(1) }

      it 'does not displays the product' do
        expect { described_class.start(argv) }.to output("Cannot find custom repository by id \"#{repository.id}\".\n").to_stderr.and output('').to_stdout
      end
    end

    context 'custom repository with products' do
      let(:repository) { create :repository, :custom }
      let(:argv) { ['products', repository.id] }

      before do
        repository_service.attach_product!(product, repository)
      end

      it('has an attached product') { expect(repository.products.count).to eq(1) }

      it 'displays the product' do
        expect { described_class.start(argv) }.to output(/.*#{product.name}.*/).to_stdout
      end
    end

    context 'custom repository without products' do
      let(:repository) { create :repository, :custom }
      let(:argv) { ['products', repository.id] }

      it('does not have an attached product') { expect(repository.products.count).to eq(0) }

      it 'displays the product' do
        expect { described_class.start(argv) }.to output('').to_stdout.and output("No products attached to repository.\n").to_stderr
      end
    end
  end
end

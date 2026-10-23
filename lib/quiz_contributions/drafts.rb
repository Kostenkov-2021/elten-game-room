# frozen_string_literal: true

require_relative 'model'

module GameRoomQuizContributions
  # Local recovery for unsaved edits and unconfirmed deliveries. Successfully
  # saved cloud drafts are removed here, not duplicated as a separate library.
  class Drafts
    using GameRoomLocalization::Translations
    FILE = 'quiz_creator_recovery.json'

    def initialize(storage, user:, current_user:)
      @storage, @user, @current_user = storage, user.to_s.downcase, current_user
    end

    # The set UUID also identifies submissions, so it must not be changed to
    # distinguish edits based on different cloud snapshots.
    def self.branch_key(value)
      JSON.generate([value['id'], value['resource_id'], value['resource_name']])
    end

    def self.same_version?(stored, reference)
      reference.key?('items') && branch_key(stored) == branch_key(reference) &&
        stored['snapshot'] == reference['snapshot'] && Model.draft(stored) == Model.draft(reference)
    end

    def list
      transaction do |account|
        entries(account).map { |_, _, value| editor_copy(value) }
      end
    end

    def save(value)
      clean = Model.draft(value)
      clean['snapshot'] = value['snapshot'] if Model::UUID.match?(value['snapshot'].to_s)
      clean['resource_id'] = value['resource_id'] if value['resource_id'].is_a?(Integer)
      clean['resource_name'] = value['resource_name'] if value['resource_name'].is_a?(String)
      transaction do |account|
        entry = entries(account).find { |_, _, old| self.class.branch_key(old) == self.class.branch_key(clean) }
        old = entry&.last
        clean['snapshot'] = SecureRandom.uuid unless old && Model.draft(old) == Model.draft(clean) && old['snapshot'] == clean['snapshot']
        if entry
          entry[0][entry[1]] = clean
        elsif account['drafts'].key?(clean['id'])
          (account['branches'] ||= {})[self.class.branch_key(clean)] = clean
        else
          account['drafts'][clean['id']] = clean
        end
      end
      Model.copy(clean)
    end

    def remove(reference)
      transaction do |account|
        entry = entries(account).find { |_, _, value| self.class.same_version?(value, reference) }
        entry[0].delete(entry[1]) if entry
        true
      end
    end

    def delivered?(key)
      transaction { |account| account['delivered'].include?(key) }
    end

    def delivered(key)
      transaction do |account|
        account['delivered'] << key unless account['delivered'].include?(key)
        account['delivered'] = account['delivered'].last(1000)
      end
    end

    private

    def entries(account)
      primary = account['drafts'].map do |id, value|
        raise Invalid, _('Invalid local drafts.') unless Model.draft(value)['id'] == id
        [account['drafts'], id, value]
      end
      extra = account.fetch('branches', {}).map do |key, value|
        Model.draft(value)
        raise Invalid, _('Invalid local drafts.') unless key == self.class.branch_key(value)
        [account['branches'], key, value]
      end
      result = primary + extra
      keys = result.map { |_, _, value| self.class.branch_key(value) }
      raise Invalid, _('Invalid local drafts.') unless keys.uniq.size == keys.size
      result
    end

    def editor_copy(value)
      # Incomplete text may be nil in recovery, but native editors consume
      # strings. Do not normalize the stored draft: its snapshot, answer
      # order and opaque recovery metadata must survive a read-only visit.
      copy = Model.copy(value)
      %w[title language description].each { |key| copy[key] = '' if copy[key].nil? }
      copy['items'].each do |question|
        %w[prompt category source note].each { |key| question[key] = '' if question[key].nil? }
        question['choices'].map! { |answer| answer.nil? ? '' : answer }
      end
      copy
    end

    def transaction
      check_account
      result = nil
      @storage.update_json(FILE, default: {'new_creator_file' => true}) do |root|
        check_account
        if root == {'new_creator_file' => true}
          raise Invalid, _('The local question drafts could not be read. The file has not been replaced.') if File.exist?(@storage.data_path(FILE))
          root.replace('version' => 1, 'accounts' => {})
        end
        unless root.is_a?(Hash) && root['version'] == 1 && root['accounts'].is_a?(Hash)
          raise Invalid, _('The local question drafts could not be read. The file has not been replaced.')
        end
        account = root['accounts'][@user] ||= {'drafts' => {}, 'delivered' => []}
        raise Invalid, _('Invalid local drafts.') unless account.is_a?(Hash) && account['drafts'].is_a?(Hash) &&
          account['delivered'].is_a?(Array) && (!account.key?('branches') || account['branches'].is_a?(Hash))
        result = yield account
        check_account
      end
      result
    end

    def check_account
      raise Unavailable, _('The signed-in account has changed.') unless @current_user.call.to_s.downcase == @user && !@user.empty?
    end
  end
end

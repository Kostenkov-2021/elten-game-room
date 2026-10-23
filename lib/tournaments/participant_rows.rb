# frozen_string_literal: true
module GameRoomTournaments
  module ParticipantRows
    module_function
    def build(members, teams)
      people = members.to_h { |person| [person.fetch('account'), person] }
      used = {}
      groups = teams.sort_by { |team| team.fetch('accounts').sort }.filter_map do |team|
        accounts = team.fetch('accounts').sort
        next unless accounts.length > 1 && accounts.uniq == accounts && accounts.all? { |account| people[account] && !used[account] }
        accounts.each { |account| used[account] = true }
        {'key'=>"team:#{accounts.join('|')}", 'accounts'=>accounts,
          'names'=>accounts.map { |account| people.fetch(account).fetch('username') }}
      end
      groups + members.reject { |person| used[person.fetch('account')] }.map do |person|
        {'key'=>"person:#{person.fetch('account')}", 'accounts'=>[person.fetch('account')], 'names'=>[person.fetch('username')]}
      end
    end
  end
end

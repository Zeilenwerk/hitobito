# encoding: utf-8

#  Copyright (c) 2012-2013, Jungwacht Blauring Schweiz. This file is part of
#  hitobito and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito.
# == Schema Information
#
# Table name: mailing_lists
#
#  id                   :integer          not null, primary key
#  name                 :string           not null
#  group_id             :integer          not null
#  description          :text
#  publisher            :string
#  mail_name            :string
#  additional_sender    :string
#  subscribable         :boolean          default(FALSE), not null
#  subscribers_may_post :boolean          default(FALSE), not null
#  anyone_may_post      :boolean          default(FALSE), not null
#

require 'spec_helper'

describe MailingList do

  let(:list)   { Fabricate(:mailing_list, group: groups(:top_layer)) }
  let(:person) { Fabricate(:person) }
  let(:event)  { Fabricate(:event, groups: [list.group], dates: [Fabricate(:event_date, start_at: Time.zone.today)]) }

  describe 'preferred_labels' do
    it 'serializes to empty array if missing' do
      expect(MailingList.new.preferred_labels).to eq []
      expect(mailing_lists(:leaders).preferred_labels).to eq []
    end

    it 'sorts array and removes duplicates' do
      list.update(preferred_labels: %w(foo bar bar baz))
      expect(list.reload.preferred_labels).to eq %w(bar baz foo)
    end

    it 'ignores blank values' do
      list.update(preferred_labels: [''])
      expect(list.reload.preferred_labels).to eq []
    end
  end

  describe 'validations' do
    it 'succeed with mail_name' do
      list.mail_name = 'aa-b'
      expect(list).to be_valid
    end

    it 'succeed with one char mail_name' do
      list.mail_name = 'a'
      expect(list).to be_valid
    end

    it 'fails with mail_name and invalid chars' do
      list.mail_name = 'a@aa'
      expect(list).to have(1).error_on(:mail_name)
    end

    it 'fails with mail_name and invalid first char' do
      list.mail_name = '-aa'
      expect(list).to have(1).error_on(:mail_name)
    end

    it 'fails with duplicate mail name' do
      Fabricate(:mailing_list, mail_name: 'foo', group: groups(:bottom_layer_one))
      list.mail_name = 'foo'
      expect(list).to have(1).error_on(:mail_name)
    end
  end

  describe '#subscribed?' do
    context 'people' do
      it 'is true if included' do
        create_subscription(person)

        expect(list.subscribed?(person)).to be_truthy
        expect(list.subscribed?(people(:top_leader))).to be_falsey
      end

      it 'is false if excluded' do
        create_subscription(person)
        create_subscription(person, true)

        expect(list.subscribed?(person)).to be_falsey
      end
    end

    context 'events' do
      it 'is true if active participation' do
        create_subscription(event)
        p = Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person

        expect(list.subscribed?(p)).to be_truthy
      end

      it 'is false if non active participation' do
        create_subscription(event)
        p = Fabricate(:event_participation, event: event).person

        expect(list.subscribed?(p)).to be_falsey
      end

      it 'is false if explicitly excluded' do
        create_subscription(event)
        p = Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person
        create_subscription(p, true)

        expect(list.subscribed?(p)).to be_falsey
      end
    end

    context 'groups' do
      it 'is true if in group' do
        create_subscription(groups(:bottom_layer_one), false,
                                  Group::BottomGroup::Leader.sti_name)
        p = Fabricate(Group::BottomGroup::Leader.name.to_sym, group: groups(:bottom_group_one_one)).person

        expect(list.subscribed?(p)).to be_truthy
      end

      it 'is false if different role in group' do
        create_subscription(groups(:bottom_layer_one), false,
                                  Group::BottomGroup::Leader.sti_name)
        p = Fabricate(Group::BottomGroup::Member.name.to_sym, group: groups(:bottom_group_one_one)).person

        expect(list.subscribed?(p)).to be_falsey
      end

      it 'is true if in group and all tags match' do
        sub = create_subscription(groups(:bottom_layer_one), false,
                                  Group::BottomGroup::Leader.sti_name)
        sub.tag_list = 'foo: bar, baz'
        sub.save!
        p = Fabricate(Group::BottomGroup::Leader.name.to_sym, group: groups(:bottom_group_one_one)).person
        p.tag_list = 'foo:bar, geez, baz'
        p.save!

        expect(list.subscribed?(p)).to be_truthy
      end

      it 'is true if in group and not all tags match' do
        sub = create_subscription(groups(:bottom_layer_one), false,
                                  Group::BottomGroup::Leader.sti_name)
        sub.tag_list = 'foo: bar, baz'
        sub.save!
        p = Fabricate(Group::BottomGroup::Leader.name.to_sym, group: groups(:bottom_group_one_one)).person
        p.tag_list = 'foo:bar'
        p.save!

        expect(list.subscribed?(p)).to be_truthy
      end

      it 'is false if in group and no tags match' do
        sub = create_subscription(groups(:bottom_layer_one), false,
                                  Group::BottomGroup::Leader.sti_name)
        sub.tag_list = 'foo: bar, baz'
        sub.save!
        p = Fabricate(Group::BottomGroup::Leader.name.to_sym, group: groups(:bottom_group_one_one)).person
        p.tag_list = 'foo:baz'
        p.save!

        expect(list.subscribed?(p)).to be_falsey
      end

      it 'is false if explicitly excluded' do
        create_subscription(groups(:bottom_layer_one), false,
                                  Group::BottomGroup::Leader.sti_name)
        p = Fabricate(Group::BottomGroup::Leader.name.to_sym, group: groups(:bottom_group_one_one)).person
        create_subscription(p, true)

        expect(list.subscribed?(p)).to be_falsey
      end
    end
  end

  describe '#people' do

    subject { list.people }


    context 'only people' do
      it 'includes single person' do
        create_subscription(person)

        is_expected.to include(person)
        expect(subject.size).to eq(1)
      end

      it 'includes various people' do
        create_subscription(person)
        create_subscription(people(:top_leader))

        is_expected.to include(person)
        is_expected.to include(people(:top_leader))
        expect(subject.size).to eq(2)
      end
    end

    context 'only events' do
      it 'includes all event participations' do
        create_subscription(event)
        leader = Fabricate(Event::Role::Leader.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation
        Fabricate(Event::Role::Treasurer.name.to_sym, participation: leader)
        p1 = leader.person
        p2 = Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person

        is_expected.to include(p1)
        is_expected.to include(p2)
        expect(subject.size).to eq(2)
      end

      it 'includes people from multiple events' do
        create_subscription(event)
        p1 = Fabricate(Event::Role::Leader.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person
        p2 = Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person

        e2 = Fabricate(:event, groups: [list.group], dates: [Fabricate(:event_date, start_at: Time.zone.today)])
        create_subscription(e2)
        p3 = Fabricate(Event::Role::Leader.name.to_sym, participation: Fabricate(:event_participation, event: e2)).participation.person
        Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: e2, person: p1))

        # only participation without role
        Fabricate(:event_participation, event: e2)

        # different event in same group
        Fabricate(Event::Role::Participant.name.to_sym,
                  participation: Fabricate(:event_participation,
                                           event: Fabricate(:event, groups: [list.group])))

        is_expected.to include(p1)
        is_expected.to include(p2)
        is_expected.to include(p3)
        expect(subject.size).to eq(3)
      end
    end

    context 'only groups' do
      it 'includes people with the given roles' do
        create_subscription(groups(:bottom_layer_one), false,
                                  Group::BottomGroup::Leader.sti_name)

        role = Group::BottomGroup::Leader.name.to_sym
        p1 = Fabricate(role, group: groups(:bottom_group_one_one)).person
        p2 = Fabricate(role, group: groups(:bottom_group_one_two)).person
        # role in a group in different hierarchy
        Fabricate(role, group: groups(:bottom_group_two_one))
        # role in a group in different hierarchy and different role in same hierarchy
        p3 = Fabricate(Group::BottomGroup::Member.name.to_sym, group: groups(:bottom_group_one_one)).person
        Fabricate(role, group: groups(:bottom_group_two_one), person: p3)
        # deleted role in the same hierarchy
        p4 = Fabricate(role, group: groups(:bottom_group_one_one), deleted_at: 1.year.ago).person

        is_expected.to include(p1)
        is_expected.to include(p2)
        is_expected.not_to include(p4)
        expect(subject.size).to eq(2)
      end

      it 'includes people with the given roles in multiple groups' do
        create_subscription(groups(:bottom_layer_one), false,
                                   Group::BottomLayer::Leader.sti_name,
                                   Group::BottomGroup::Leader.sti_name)
        create_subscription(groups(:bottom_group_one_one), false,
                                   Group::BottomGroup::Member.sti_name)

        p1 = Fabricate(Group::BottomLayer::Leader.name.to_sym, group: groups(:bottom_layer_one)).person
        p2 = Fabricate(Group::BottomGroup::Leader.name.to_sym, group: groups(:bottom_group_one_one)).person
        p3 = Fabricate(Group::BottomGroup::Member.name.to_sym, group: groups(:bottom_group_one_one)).person
        # role in a group in different hierarchy
        Fabricate(Group::BottomGroup::Leader.name.to_sym, group: groups(:bottom_group_two_one))
        Fabricate(Group::BottomGroup::Member.name.to_sym, group: groups(:bottom_group_one_two))

        is_expected.to include(p1)
        is_expected.to include(p2)
        is_expected.to include(p3)
        expect(subject.size).to eq(3)
      end
    end

    context 'people with excluded' do
      it 'excludes people' do
        create_subscription(person)
        create_subscription(people(:top_leader))
        create_subscription(person, true)

        is_expected.to include(people(:top_leader))
        expect(subject.size).to eq(1)
      end
    end

    context 'events with excluded' do
      it 'excludes person from events' do
        create_subscription(event)
        p1 = Fabricate(Event::Role::Leader.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person
        p2 = Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person

        e2 = Fabricate(:event, groups: [list.group], dates: [Fabricate(:event_date, start_at: Time.zone.today)])
        create_subscription(e2)
        p3 = Fabricate(Event::Role::Leader.name.to_sym, participation: Fabricate(:event_participation, event: e2)).participation.person
        Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: e2, person: p1))

        create_subscription(p1, true)

        is_expected.to include(p2)
        is_expected.to include(p3)
        expect(subject.size).to eq(2)
      end
    end

    context 'groups with excluded' do
      it 'excludes person from groups' do
        create_subscription(groups(:bottom_layer_one), false,
                                  Group::BottomGroup::Leader.sti_name)

        role = Group::BottomGroup::Leader.name.to_sym
        p1 = Fabricate(role, group: groups(:bottom_group_one_one)).person
        p2 = Fabricate(role, group: groups(:bottom_group_one_two)).person

        create_subscription(p2, true)

        is_expected.to include(p1)
        expect(subject.size).to eq(1)
      end
    end

    context 'all' do
      it 'includes different people from events and groups' do
        # people
        create_subscription(person)
        create_subscription(people(:top_leader))

        # events
        create_subscription(event)
        pe1 = Fabricate(Event::Role::Leader.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person
        pe2 = Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person

        e2 = Fabricate(:event, groups: [list.group], dates: [Fabricate(:event_date, start_at: Time.zone.today + 200)])
        create_subscription(e2)
        pe3 = Fabricate(Event::Role::Leader.name.to_sym, participation: Fabricate(:event_participation, event: e2)).participation.person
        Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: e2, person: pe1))


        # groups
        create_subscription(groups(:bottom_layer_one), false,
                                   Group::BottomLayer::Leader.sti_name,
                                   Group::BottomGroup::Leader.sti_name)
        sub2 = create_subscription(groups(:bottom_group_one_one), false,
                                   Group::BottomGroup::Member.sti_name)
        sub2.tag_list = 'foo, bar'
        sub2.save!

        pg1 = Fabricate(Group::BottomLayer::Leader.name.to_sym, group: groups(:bottom_layer_one)).person
        pg2 = Fabricate(Group::BottomGroup::Leader.name.to_sym, group: groups(:bottom_group_one_one)).person
        pg3 = Fabricate(Group::BottomGroup::Member.name.to_sym, group: groups(:bottom_group_one_one)).person
        pg3.tag_list = 'foo, bar, baz'
        pg3.save!
        pg4 = Fabricate(Group::BottomGroup::Member.name.to_sym, group: groups(:bottom_group_one_one)).person
        # role in a group in different hierarchy
        Fabricate(Group::BottomGroup::Leader.name.to_sym, group: groups(:bottom_group_two_one))
        Fabricate(Group::BottomGroup::Member.name.to_sym, group: groups(:bottom_group_one_two))

        is_expected.to include(person)
        is_expected.to include(people(:top_leader))
        is_expected.to include(pe1)
        is_expected.to include(pe2)
        is_expected.to include(pe3)
        is_expected.to include(pg1)
        is_expected.to include(pg2)
        is_expected.to include(pg3)
        is_expected.not_to include(pg4)
        expect(subject.size).to eq(8)
      end

      it 'includes overlapping people from events and groups' do
        # people
        create_subscription(people(:top_leader))

        # events
        create_subscription(event)
        pe1 = Fabricate(Event::Role::Leader.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person
        pe2 = Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person

        e2 = Fabricate(:event, groups: [list.group], dates: [Fabricate(:event_date, start_at: Time.zone.today - 100)])
        create_subscription(e2)
        pe3 = Fabricate(Event::Role::Leader.name.to_sym, participation: Fabricate(:event_participation, event: e2)).participation.person
        Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: e2, person: pe1))


        # groups
        create_subscription(groups(:bottom_layer_one), false,
                                   Group::BottomLayer::Leader.sti_name,
                                   Group::BottomGroup::Leader.sti_name)
        create_subscription(groups(:bottom_group_one_one), false,
                                   Group::BottomGroup::Member.sti_name)

        pg1 = Fabricate(Group::BottomLayer::Leader.name.to_sym, group: groups(:bottom_layer_one)).person
        pg2 = Fabricate(Group::BottomGroup::Leader.name.to_sym, group: groups(:bottom_group_one_one)).person
        Fabricate(Group::BottomGroup::Member.name.to_sym, group: groups(:bottom_group_one_one), person: pe3)

        create_subscription(pg2)

        is_expected.to include(people(:top_leader))
        is_expected.to include(pe1)
        is_expected.to include(pe2)
        is_expected.to include(pe3)
        is_expected.to include(pg1)
        is_expected.to include(pg2)
        expect(subject.size).to eq(6)
      end
    end

    context 'all with excluded' do

      it 'excludes overlapping people from events and groups' do
        # people
        create_subscription(people(:top_leader))

        # events
        create_subscription(event)
        pe1 = Fabricate(Event::Role::Leader.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person
        pe2 = Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: event)).participation.person

        e2 = Fabricate(:event, groups: [list.group], dates: [Fabricate(:event_date, start_at: Time.zone.today)])
        create_subscription(e2)
        pe3 = Fabricate(Event::Role::Leader.name.to_sym, participation: Fabricate(:event_participation, event: e2)).participation.person
        Fabricate(Event::Role::Participant.name.to_sym, participation: Fabricate(:event_participation, event: e2, person: pe1))


        # groups
        create_subscription(groups(:bottom_layer_one), false,
                                   Group::BottomLayer::Leader.sti_name,
                                   Group::BottomGroup::Leader.sti_name)
        create_subscription(groups(:bottom_group_one_one), false,
                                   Group::BottomGroup::Member.sti_name)

        pg1 = Fabricate(Group::BottomLayer::Leader.name.to_sym, group: groups(:bottom_layer_one)).person
        pg2 = Fabricate(Group::BottomGroup::Leader.name.to_sym, group: groups(:bottom_group_one_one)).person
        Fabricate(Group::BottomGroup::Member.name.to_sym, group: groups(:bottom_group_one_one), person: pe3)

        create_subscription(pg2, true)
        create_subscription(pe1, true)

        is_expected.to include(people(:top_leader))
        is_expected.to include(pe2)
        is_expected.to include(pe3)
        is_expected.to include(pg1)
        expect(subject.size).to eq(4)

        expect(list.subscribed?(people(:top_leader))).to be_truthy
        expect(list.subscribed?(pe2)).to be_truthy
        expect(list.subscribed?(pe3)).to be_truthy
        expect(list.subscribed?(pg1)).to be_truthy
        expect(list.subscribed?(pg2)).to be_falsey
        expect(list.subscribed?(pe1)).to be_falsey
      end
    end
  end

  def create_subscription(subscriber, excluded = false, *role_types)
    sub = list.subscriptions.new
    sub.subscriber = subscriber
    sub.excluded = excluded
    sub.related_role_types = role_types.collect { |t| RelatedRoleType.new(role_type: t) }
    sub.save!
    sub
  end

end

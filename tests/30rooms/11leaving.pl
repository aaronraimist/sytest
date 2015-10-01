use List::Util qw( first );

my $room_id;

prepare "Setup a room, and have the first user leave (SPEC-216)",
    requires => [qw(
        make_test_room change_room_powerlevels do_request_json_for user
        more_users
        can_create_room
    )],

    do => sub {
        my (
            $make_test_room, $change_room_powerlevels, $do_request_json_for,
            $user_a, $more_users
        ) = @_;
        my $user_b = $more_users->[1];

        my $send_text_message = sub {
            my ( $user, $room_id, $message ) = @_;
            $do_request_json_for->( $user,
                method => "POST",
                uri => "/api/v1/rooms/$room_id/send/m.room.message",
                content => {
                    "body" => $message, "msgtype" => "m.room.text",
                },
            )
        };

        my $set_room_state = sub {
            my ( $user, $room_id, $type, $state_key, $content ) = @_;
            $do_request_json_for->( $user,
                method => "PUT",
                uri => "/api/v1/rooms/$room_id/state/$type/$state_key",
                content => $content,
            )
        };

        my $leave_room = sub {
            my ( $user, $room_id ) = @_;
            $do_request_json_for->( $user,
                method => "POST",
                uri => "/api/v1/rooms/$room_id/leave",
                content => {},
            )
        };

        $make_test_room->( [$user_a, $user_b] )->then( sub {
            ( $room_id ) = @_;

            $change_room_powerlevels->( $user_a, $room_id, sub {
                my ( $levels ) = @_;
                # Set user B's power level so that they can set the room
                # name. By default the level to set a room name is 50. But
                # we set the level to 50 anyway incase the default changes.
                $levels->{events}{"m.room.name"} = 50;
                $levels->{events}{"madeup.test.state"} = 50;
                $levels->{users}{ $user_b->user_id } = 50;
            })
        })->then( sub {
            $set_room_state->($user_b, $room_id, "m.room.name", "", {
                "name" => "N1. B's room name before A left",
            })
        })->then( sub {
            $set_room_state->($user_b, $room_id, "madeup.test.state", "", {
                "body" => "S1. B's state before A left",
            })
        })->then( sub {
            $send_text_message->($user_b, $room_id, "M1. B's message before A left")
        })->then( sub {
            $send_text_message->($user_b, $room_id, "M2. B's message before A left")
        })->then( sub {
            $leave_room->($user_a, $room_id)
        })->then( sub {
            $send_text_message->($user_b, $room_id, "M3. B's message after A left")
        })->then( sub {
            $set_room_state->($user_b, $room_id, "m.room.name", "", {
                "name" => "N2. B's room name after A left",
            })
        })->then( sub {
            $set_room_state->($user_b, $room_id, "madeup.test.state", "", {
                "body" => "S2. B's state after A left",
            })
        })
    };

test "A departed room is still included in /initialSync (SPEC-216)",
    requires => [qw( do_request_json )],

    check => sub {
        my ( $do_request_json ) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/initialSync",
            params => { limit => 2 },
        )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( rooms ) );

            my $room = first { $_->{room_id} eq $room_id } @{$body->{rooms}}
                or die "Departed room not in /initialSync";

            require_json_keys( $room, qw( state messages membership) );

            $room->{membership} eq "leave" or die "Membership is not leave";

            my $madeup_test_state =
                first { $_->{type} eq "madeup.test.state" } @{$room->{state}};

            $madeup_test_state->{content}{body}
                eq "S1. B's state before A left"
                or die "Received state that happened after leaving the room";

            $room->{messages}{chunk}[0]{content}{body}
                eq "M2. B's message before A left"
                or die "Received message that happened after leaving the room";

            Future->done(1);
        })
    };

test "Can get rooms/{roomId}/initialSync for a departed room (SPEC-216)",
    requires => [qw( do_request_json )],

    check => sub {
        my ( $do_request_json ) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$room_id/initialSync",
            params => { limit => 2 },
        )->then( sub {
            my ( $room ) = @_;

            require_json_keys( $room, qw( state messages membership ) );

            $room->{membership} eq "leave" or die "Membership is not leave";

            my $madeup_test_state =
                first { $_->{type} eq "madeup.test.state" } @{$room->{state}};

            $madeup_test_state->{content}{body} eq "S1. B's state before A left"
                or die "Received state that happened after leaving the room";

            $room->{messages}{chunk}[0]{content}{body}
                eq "M2. B's message before A left"
                or die "Received message that happened after leaving the room";

            not @{$room->{presence}}
                or die "Received presence information after leaving the room";

            not @{$room->{receipts}}
                or die "Received receipts after leaving the room";

            Future->done(1);
        })
    };

test "Can get rooms/{roomId}/state for a departed room (SPEC-216)",
    requires => [qw( do_request_json )],

    check => sub {
        my ( $do_request_json ) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$room_id/state",
        )->then( sub {
            my ( $state ) = @_;

            my $madeup_test_state =
                first { $_->{type} eq "madeup.test.state" } @{$state};

            $madeup_test_state->{content}{body}
                eq "S1. B's state before A left"
                or die "Received state that happened after leaving the room";

            Future->done(1);
        })
    };

test "Can get rooms/{roomId}/members for a departed room (SPEC-216)",
    requires => [qw( user do_request_json )],

    check => sub {
        my ( $user, $do_request_json ) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$room_id/members",
        )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( chunk ) );

            my $membership =
                first { $_->{state_key} eq $user->user_id } @{$body->{chunk}}
                or die "Couldn't find own membership event";

            $membership->{content}{membership} eq "leave"
                or die "My membership event wasn't leave";

            Future->done(1);
        })
    };

test "Can get rooms/{roomId}/messages for a departed room (SPEC-216)",
    requires => [qw( do_request_json)],

    check => sub {
        my ( $do_request_json ) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$room_id/messages",
            params => {limit => 2, dir => 'b'},
        )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( chunk ) );

            $body->{chunk}[1]{content}{body} eq "M2. B's message before A left"
                or die "Received message that happened after leaving the room";

            Future->done(1);
        })
    };

test "Can get rooms/{roomId}/state/m.room.name for a departed room (SPEC-216)",
    requires => [qw( do_request_json )],

    check => sub {
        my ( $do_request_json ) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$room_id/state/m.room.name",
        )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( name ) );

            $body->{name} eq "N1. B's room name before A left"
                or die "Received message that happened after leaving the room";

            Future->done(1);
        })
    };

test "Getting messages going forward is limited for a departed room (SPEC-216)",
    requires => [qw( do_request_json )],

    check => sub {
        my ( $do_request_json ) = @_;

        # TODO: The "t10000-0_0_0_0" token format is synapse specific.
        #  However there isn't a way in the matrix C-S protocol to learn the
        #  latest token for a room that you aren't in. It may be necessary
        #  to add some extra APIs to matrix for learning this sort of thing for
        #  testing security.
        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$room_id/messages",
            params => {limit => 2, to => "t10000-0_0_0_0"},
        )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( chunk ) );

            not @{$body->{chunk}}
                or die "Received message that happened after leaving the room";

            Future->done(1);
        })
    };
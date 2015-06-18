# A handy little structure for other scripts to find in 'user' and 'more_users'
struct User => [qw( http user_id access_token eventstream_token saved_events pending_get_events )];

test "GET /login yields a set of flows",
   requires => [qw( first_http_client )],

   provides => [qw( can_login_password_flow )],

   check => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         uri => "/login",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( flows ));
         ref $body->{flows} eq "ARRAY" or die "Expected 'flows' as a list";

         my $has_login_flow;

         foreach my $idx ( 0 .. $#{ $body->{flows} } ) {
            my $flow = $body->{flows}[$idx];

            # TODO(paul): Spec is a little vague here. Spec says that every
            #   option needs a 'stages' key, but the implementation omits it
            #   for options that have only one stage in their flow.
            ref $flow->{stages} eq "ARRAY" or defined $flow->{type} or
               die "Expected flow[$idx] to have 'stages' as a list or a 'type'";

            $has_login_flow++ if $flow->{type} eq "m.login.password" or
               @{ $flow->{stages} } == 1 && $flow->{stages}[0] eq "m.login.password"
         }

         $has_login_flow and
            provide can_login_password_flow => 1;

         Future->done(1);
      });
   };

test "POST /login can log in as a user",
   requires => [qw( first_http_client can_register can_login_password_flow )],

   provides => [qw( can_login user first_home_server do_request_json_for do_request_json )],

   do => sub {
      my ( $http, $login_details ) = @_;
      my ( $user_id, $password ) = @$login_details;

      $http->do_request_json(
         method => "POST",
         uri    => "/login",

         content => {
            type     => "m.login.password",
            user     => $user_id,
            password => $password,
         },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( access_token home_server ));

         provide can_login => 1;

         my $access_token = $body->{access_token};

         provide user => my $user = User( $http, $user_id, $access_token, undef, [], undef );

         provide first_home_server => $body->{home_server};

         provide do_request_json_for => my $do_request_json_for = sub {
            my ( $user, %args ) = @_;

            my $user_id = $user->user_id;
            ( my $uri = delete $args{uri} ) =~ s/:user_id/$user_id/g;

            my %params = (
               access_token => $user->access_token,
               %{ delete $args{params} || {} },
            );

            $user->http->do_request_json(
               uri    => $uri,
               params => \%params,
               %args,
            );
         };

         provide do_request_json => sub {
            $do_request_json_for->( $user, @_ );
         };

         Future->done(1);
      });
   };

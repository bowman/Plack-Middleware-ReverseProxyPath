use strict;
use warnings;

use Test::More;
use Plack::Test;
use Plack::Request;
# use Plack::Builder;
use Plack::Middleware::ReverseProxyPath;
use Plack::App::URLMap;
use HTTP::Request::Common;

my $XFSN  = 'X-Forwarded-Script-Name';
my $XTP   = 'X-Traversal-Path';
my $HXFSN = 'HTTP_X_FORWARDED_SCRIPT_NAME';
my $HXTP  = 'HTTP_X_TRAVERSAL_PATH';

my $expecting_failure;

my $base_inner = \&echo_base;
my $env_inner  = \&echo_env;

my $base_wrapped = Plack::Middleware::ReverseProxyPath->wrap($base_inner);
my $env_wrapped  = Plack::Middleware::ReverseProxyPath->wrap($env_inner);

my $url_map = Plack::App::URLMap->new;
$url_map->map( "/base_inner"     => $base_inner );
$url_map->map( "/env_inner"      => $env_inner );
$url_map->map( "/base_wrapped"   => $base_wrapped );
$url_map->map( "/env_wrapped"    => $env_wrapped );
# $url_map->map( "/deep"           => $url_map ); # miyagawa: probably not ok
$url_map->map( "/deep/base_inner"     => $base_inner );
$url_map->map( "/deep/env_inner"      => $env_inner );
$url_map->map( "/deep/base_wrapped"   => $base_wrapped );
$url_map->map( "/deep/env_wrapped"    => $env_wrapped );
$url_map->map( "/deep/deep/base_inner"     => $base_inner );
$url_map->map( "/deep/deep/env_inner"      => $env_inner );
$url_map->map( "/deep/deep/base_wrapped"   => $base_wrapped );
$url_map->map( "/deep/deep/env_wrapped"    => $env_wrapped );

# request => sub { response checks }

my @tests = (
    # sanity check tests, not using rpp
    (GET "/base_inner") => sub {
        like $_->content, qr{ /base_inner $ }x;
    },

    (GET "/env_inner") => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /env_inner $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_inner $ }xm;
    },

    (GET "/base_inner/path") => sub {
        like $_->content, qr{ /base_inner $ }x;
    },

    (GET "/env_inner/path") => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /env_inner $ }xm;
        like $_->content, qr{ ^ PATH_INFO:   \s /path $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_inner/path $ }xm;
    },

    (GET "/deep/base_inner") => sub {
        like $_->content, qr{ /deep/base_inner $ }x;
    },

    (GET "/deep/env_inner") => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /deep/env_inner $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /deep/env_inner $ }xm;
    },

    (GET "/deep/deep/base_inner") => sub {
        like $_->content, qr{ /deep/deep/base_inner $ }x;
    },

    (GET "/deep/deep/env_inner") => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /deep/deep/env_inner $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /deep/deep/env_inner $ }xm;
    },

    # extra headers ignored
    (GET "/base_inner", $XFSN => '/this', $XTP => '/that' ) => sub {
        like $_->content, qr{ /base_inner $ }x;
    },

    (GET "/env_inner", $XFSN => '/this', $XTP => '/that' ) => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /env_inner $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_inner $ }xm;
        like $_->content, qr{ ^ $HXFSN : \s /this $ }xm;
        like $_->content, qr{ ^ $HXTP : \s /that $ }xm;
    },

    # now we go via ReverseProxyPath to test it
    #  (all these are the same as above to THIS_MARKER)
    (GET "/base_wrapped") => sub {
        like $_->content, qr{ /base_wrapped $ }x;
    },

    (GET "/env_wrapped") => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /env_wrapped $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped $ }xm;
    },

    (GET "/base_wrapped/path") => sub {
        like $_->content, qr{ /base_wrapped $ }x;
    },

    (GET "/env_wrapped/path") => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /env_wrapped $ }xm;
        like $_->content, qr{ ^ PATH_INFO:   \s /path $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped/path $ }xm;
    },

    (GET "/deep/base_wrapped") => sub {
        like $_->content, qr{ /deep/base_wrapped $ }x;
    },

    (GET "/deep/env_wrapped") => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /deep/env_wrapped $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /deep/env_wrapped $ }xm;
    },

    (GET "/deep/deep/base_wrapped") => sub {
        like $_->content, qr{ /deep/deep/base_wrapped $ }x;
    },

    (GET "/deep/deep/env_wrapped") => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /deep/deep/env_wrapped $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /deep/deep/env_wrapped $ }xm;
    },

    # extra headers are used (THIS_MARKER)

    # bad headers => server error
    (GET "/base_wrapped", $XFSN => '/this', $XTP => '/that' ) => sub {
        is $_->code, 500; # bogus headers cause an error
        like $_->content, qr{is not a prefix of};
    },

    (GET "/base_wrapped", $XFSN => '/this', $XTP => '/base_wrapped' ) => sub {
        like $_->content, qr{ /this $ }x, "replace prefix $XFSN";
    },

    (GET "/env_wrapped", $XFSN => '/this', $XTP => '/env_wrapped' ) => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /this $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped $ }xm;
    },

    # check extra headers are there too.
    (GET "/env_wrapped", $XFSN => '/this', $XTP => '/env_wrapped' ) => sub {
        like $_->content, qr{ ^ $HXFSN : \s /this $ }xm;
        like $_->content, qr{ ^ $HXTP : \s /env_wrapped $ }xm;
    },

    (GET "/base_wrapped/path", $XFSN => '/this', $XTP => '/base_wrapped' )
    => sub {
        like $_->content, qr{ /this $ }x, "replace prefix $XFSN";
    },

    (GET "/env_wrapped/path", $XFSN => '/this', $XTP => '/env_wrapped' )
    => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /this $ }xm;
        like $_->content, qr{ ^ PATH_INFO:   \s /path $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped/path $ }xm;
        like $_->content, qr{ ^ $HXFSN : \s /this $ }xm;
        like $_->content, qr{ ^ $HXTP : \s /env_wrapped $ }xm;
    },

    (GET "/deep/base_wrapped", $XFSN => '/this', $XTP => '/deep/base_wrapped' )
    => sub {
        like $_->content, qr{ /this $ }x, "replace prefix $XFSN";
    },

    (GET "/deep/env_wrapped", $XFSN => '/this', $XTP => '/deep/env_wrapped' )
    => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /this $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /deep/env_wrapped $ }xm;
        like $_->content, qr{ ^ $HXFSN : \s /this $ }xm;
        like $_->content, qr{ ^ $HXTP : \s /deep/env_wrapped $ }xm;
    },

    # borrow from PATH_INFO
    (GET "/base_wrapped/path/more",
        $XFSN => '/this', $XTP => '/base_wrapped/path' )
    => sub {
        like $_->content, qr{ /this $ }x, "borrow from PATH_INFO";
    },

    (GET "/env_wrapped/path/more",
        $XFSN => '/this', $XTP => '/env_wrapped/path' )
    => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /this $ }xm;
        like $_->content, qr{ ^ PATH_INFO:   \s /more $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped/path/more $ }xm;
    },

    # trailing / on request
    (GET "/base_wrapped/", $XFSN => '/this', $XTP => '/base_wrapped' )
    => sub {
        like $_->content, qr{ /this $ }x, "trailing / on request";
    },

    (GET "/env_wrapped/", $XFSN => '/this', $XTP => '/env_wrapped' )
    => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s /this $ }xm;
        like $_->content, qr{ ^ PATH_INFO:   \s / $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped/ $ }xm;
    },

    # empty replacement
    (GET "/base_wrapped", $XFSN => '', $XTP => '/base_wrapped' ) => sub {
        like $_->content, qr{ / $ }x, "empty replacement";
    },

    (GET "/env_wrapped", $XFSN => '', $XTP => '/env_wrapped' ) => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped $ }xm;
    },

    (GET "/deep/base_wrapped", $XFSN => '', $XTP => '/deep/base_wrapped' )
    => sub {
        like $_->content, qr{ / $ }x, "replace prefix $XFSN";
    },

    (GET "/deep/env_wrapped", $XFSN => '', $XTP => '/deep/env_wrapped' )
    => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /deep/env_wrapped $ }xm;
    },

    (GET "/base_wrapped/path/more",
        $XFSN => '', $XTP => '/base_wrapped/path' )
    => sub {
        like $_->content, qr{ / $ }x, "borrow from PATH_INFO";
    },

    (GET "/env_wrapped/path/more",
        $XFSN => '', $XTP => '/env_wrapped/path' )
    => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s $ }xm;
        like $_->content, qr{ ^ PATH_INFO:   \s /more $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped/path/more $ }xm;
    },

# From PSGI spec
# One of SCRIPT_NAME or PATH_INFO MUST be set. When REQUEST_URI is /,
# PATH_INFO should be / and SCRIPT_NAME should be empty. SCRIPT_NAME
# MUST NOT be /, but MAY be empty.

    # borrowed path_info and trailing / on request
    (GET "/base_wrapped/path/",
        $XFSN => '', $XTP => '/base_wrapped/path' )
    => sub {
        like $_->content, qr{ / $ }x, "borrow from PATH_INFO, trailing req /";
    },

    (GET "/env_wrapped/path/",
        $XFSN => '', $XTP => '/env_wrapped/path' )
    => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s $ }xm;
        like $_->content, qr{ ^ PATH_INFO:   \s / $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped/path/ $ }xm;
    },

    # doubled // (see Plack::Middleware::NoMultipleSlashes)
    (GET "/base_wrapped//path///",
        $XFSN => '/', $XTP => '/base_wrapped//path//' ) # 
    => sub {
        like $_->content, qr{ [^/]/ $ }x, "multiple //";
    },
    (GET "/env_wrapped//path///",
        $XFSN => '/', $XTP => '/env_wrapped//path//' )
    => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s $ }xm; # should never be just /
        like $_->content, qr{ ^ PATH_INFO:   \s / $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped//path/// $ }xm;
    },

    # trailing / on headers

    # '/' replacement (this is a misconfiguration, use '')
    (GET "/base_wrapped", $XFSN => '/', $XTP => '/base_wrapped' ) => sub {
        like $_->content, qr{ / $ }x, "/ replacement";
    },

    (GET "/env_wrapped", $XFSN => '/', $XTP => '/env_wrapped' ) => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped $ }xm;
    },

    # '/' replaced (this is a misconfiguration, use '')
    (GET "/base_wrapped/", $XFSN => '', $XTP => '/base_wrapped/' ) => sub {
        like $_->content, qr{ [^/]/ $ }x, "trailing / trav path";
    },

    (GET "/env_wrapped/", $XFSN => '', $XTP => '/env_wrapped/' ) => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped/ $ }xm;
    },


    (GET "/base_wrapped/more", $XFSN => '/', $XTP => '/base_wrapped/' )
    => sub {
        like $_->content, qr{ [^/]/ $ }x, "/ replacement";
    },

    (GET "/env_wrapped/more", $XFSN => '/', $XTP => '/env_wrapped/' ) => sub {
        like $_->content, qr{ ^ SCRIPT_NAME: \s $ }xm;
        # PSGI requires PATH_INFO to start with a /
        like $_->content, qr{ ^ PATH_INFO: \s /more $ }xm;
        like $_->content, qr{ ^ REQUEST_URI: \s /env_wrapped/more $ }xm;
    },

);

# this doesn't return is_success
test_psgi
    app => $url_map,
    client => sub {
        my $cb  = shift;
        my $req = GET "/";
        note $req->as_string;
        my $res = $cb->($req);
        local $_ = $res;
        is $_->code, 404;
        like $_->content, qr/Not Found/;
    };

while ( my ($req, $test) = splice( @tests, 0, 2 ) ) {
    test_psgi
        app => $url_map,
        client => sub {
            my $cb  = shift;
            note $req->as_string;
            my $res = $cb->($req);
            local $_ = $res;
            $test->($res, $req);
            # ok($res->is_success(), "is_success")
                # or diag $req->as_string, $res->as_string;
        };
}

# no headers == unwrapped

done_testing();

sub echo_base {
    [200, [ qw(Content-type text/plain) ],
        [ Plack::Request->new(shift)->base . "\n" ] ]
}

sub echo_env {
    my ($env) = @_;
    [200, [ qw(Content-type text/plain) ],
        [ map { "$_: $env->{$_}\n" } keys %$env ] ]
}

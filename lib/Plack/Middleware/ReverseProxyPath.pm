package Plack::Middleware::ReverseProxyPath;

use strict;
use warnings;
use parent qw(Plack::Middleware);
our $VERSION = '0.01';

sub call {
    my $self = shift;
    my $env = shift;

    if (    $env->{'HTTP_X_FORWARDED_SCRIPT_NAME'}
         || $env->{'HTTP_X_SCRIPT_NAME'}
         || $env->{'HTTP_X_TRAVERSAL_PATH'} ) {

        my $x_script_name    = $env->{'HTTP_X_FORWARDED_SCRIPT_NAME'}   ||
                               $env->{'HTTP_X_SCRIPT_NAME'}             || '';
        my $x_traversal_path = $env->{'HTTP_X_TRAVERSAL_PATH'}          || '';
        my $script_name      = $env->{SCRIPT_NAME};

        # replace $script_name . $path_info
        # prefix of $x_traversal_path with $x_script_name
        if ( length $script_name >= length $x_traversal_path ) {
            $script_name =~ s/^\Q$x_traversal_path\E/$x_script_name/
                or _throw_error(
                    "HTTP_X_TRAVERSAL_PATH: $x_traversal_path\n" .
                    "is not a prefix of \n" .
                    "SCRIPT_NAME: $script_name\n" );
        } else {
            # $x_traversal_path is longer, borrow from path_info
            $x_traversal_path =~ s/^\Q$script_name\E//
                or _throw_error(
                    "SCRIPT_NAME $script_name\n" .
                    "is not a prefix of \n" .
                    "HTTP_X_TRAVERSAL_PATH: $x_traversal_path\n" );
            $script_name = $x_script_name;

            $env->{PATH_INFO} =~ s/^\Q$x_traversal_path\E//
                or _throw_error(
                    "Fragment: $x_traversal_path\n" .
                    "is not a prefix of \n" .
                    "PATH_INFO: $env->{PATH_INFO}\n" .
                    " SCRIPT_NAME: $script_name\n" .
                    " HTTP_X_TRAVERSAL_PATH: $env->{HTTP_X_TRAVERSAL_PATH}\n" );
        }
        $env->{SCRIPT_NAME} = $script_name;

        # don't touch REQUEST_URI, it will continue to refer to the original
    }

    $self->app->($env);
}

sub _throw_error {
    my ($message) = @_;
    die Plack::Middleware::ReverseProxyPath::Exception->new($message);
    die Plack::Util::inline_object(
        code => sub { 500 },
        as_string => sub { $message },
    );
}

{
    package Plack::Middleware::ReverseProxyPath::Exception;
    use overload '""' => \&as_string;
    sub new {
        my ($class, $message) = @_;
        return bless { message => $message }, $class;
    }
    sub code { 500 }
    sub as_string { $_[0]->{message} }
}

1;

__END__

=head1 NAME

Plack::Middleware::ReverseProxyPath - adjust proxied env to match client-facing

=head1 SYNOPSIS

#!perl -MPlack::Runner
#line 85
  sub mw(&);

  use Plack::Builder;

  # Configure your reverse proxy (perlbal, varnish, apache, squid)
  # to send X-Forwarded-Script-Name and X-Traversal-Path headers.
  # This example just uses Plack::App::Proxy to demonstrate:
  sub proxy_builder {
    require Plack::App::Proxy;

    mount "http://localhost/fepath/from" => builder {
        enable mw {
            my ($app, $env) = @_;
            $env->{'HTTP_X_FORWARDED_SCRIPT_NAME'} = '/fepath/from';
            $env->{'HTTP_X_TRAVERSAL_PATH'}        = '/bepath/to';
            $app->($env);
        };
#         enable sub {
#            my $app = shift;
#            sub {
#                my $env = shift;
#                $env->{'X-Forwarded-Script-Name'} = '/fepath/from';
#                $env->{'X-Traversal-Path'}        = '/bepath/to';
#                $app->($env);
#            };
#        };
        Plack::App::Proxy->new(remote => 'http://localhost:5000/bepath/to')->to_app;
        #\&echo_env;
    };
    mount "http://localhost/otherfe" => sub {
        my $env = shift;
        $env->{'X-Forwarded-Script-Name'} = '/otherfe';
        $env->{'X-Traversal-Path'}        = '/bepath/to';
        Plack::App::Proxy->new(remote => 'http://0:5000')->to_app;
    };
  };

  # Then in your PSGI backend
  my $app = builder {

    # /bepath/to/* is proxied
    mount "/bepath/to" => builder {

      # ReverseProxy sets scheme, host and port using standard headers
      enable "ReverseProxy";

      # ReverseProxyPath adjusts SCRIPT_NAME and PATH_INFO using new headers
      enable "ReverseProxyPath";

      # $req->base + $req->path now is the client-facing url
      # so URLs, Set-Cookie, Location can work naively
      mount "/base" => \&echo_base;
      mount "/env"  => \&echo_env;

    };

    #mount "/" => \&echo_base;

    # proxy to myself to keep the synopsis short
    proxy_builder();
  };

  sub echo_base { require Plack::Request;
      [200, [ qw(Content-type text/plain) ],
            [ Plack::Request->new(shift)->base . "\n" ] ]
  }
  sub echo_env {
      my ($env) = @_;
      [200, [ qw(Content-type text/plain) ],
            [ map { "$_: $env->{$_}\n" } keys %$env ] ]
  }
  sub mw(&) { my $code = shift;
    sub { my $app = shift; sub { $code->($app, @_); } } };

  Plack::Runner->new->run($app);
__END__

=head1 DESCRIPTION

Use case: reverse proxying /sub/path/ to http://0:5000/other/path/ .
This middleware sits on the backend and uses headers sent by the proxy
to hide the proxy plumbing from the backend app.

Plack::Middleware::ReverseProxy does the host, port and scheme.
Plack::Middleware::ReverseProxyPath adds handling of paths.

The goal is to allow proxied backends to reconstruct and use
the client-facing url.  ReverseProxy does most of the work
and ReverseProxyPath does the paths.  The inner app can simply
use $req->base to redirect, set cookies and the like.

I find the term B<reverse proxy> leads to confusion, so I'll
use B<front-end> to refer to the reverse proxy (eg. squid) which
the client hits first, and B<back-end> to refer to the server
that runs your PSGI application (eg. starman).



Plack::Middleware::ReverseProxyPath adjusts SCRIPT_NAME and PATH_INFO
based on headers from a reverse proxy so that it's inner app can pretend
there is no proxy there.  This is useful when you aren't proxying and
entire server, but only a deeper path.  In Apache terms:

  ProxyPass /mirror/foo/ http://localhost:5000/bar/

It should be used with Plack::Middleware::ReverseProxy which does equivalent
adjustments to the scheme, host and port environment attributes.


The reverse proxy then no longer needs ProxyPassReverse,
ProxyPassReverseCookieDomain, ProxyPassReverseCookiePath,
mod_proxy_html and other proxy-level patch-ups.

=head2 Required Headers

In order for this middleware to perform the path adjustments
you will need to configure your reverse proxy to send the following
headers (as applicable):

=over 4

=item X-Forwarded-Script-Name

The front-end prefix being forwarded FROM.

(X-Script-Name is used by wsgiproxy and can be used instead).

The value of SCRIPT_NAME on the reverse proxy (which is not the request
path used on the backend).

=item X-Traversal-Path

The backend prefix being forwarded TO.

This is the part of the backend uri that is plumbing which
will be hidden from the app.

If you aren't forwarding to the root of a server, but to some
deeper path, this contains the deeper path portion. So if you
forward to http://localhost:8080/myapp, and there is a request for
/article/1, then the full path forwarded to will be
/myapp/article/1. X-Traversal-Path will contain /myapp.

=back

=head2 Path Adjustment Logic

If there is either X-Traversal-Path or X-Script-Name:

  SCRIPT_NAME . PATH_INFO =~ s/^X-Traversal-Path/X-Script-Name/

The X-Traversal-Path prefix will be stripped from SCRIPT_NAME
(borrowing from PATH_INFO if anything is left over) and
SCRIPT_NAME will be prefixed with X-Script-Name.

In the absence of reverse proxy headers, leave SCRIPT_NAME and PATH_INFO alone.
This allows direct connections to the backend to function.
Also, leave REQUEST_URI alone with the old/original value.

Front-ends should clear client-sent X-Traversal-Path and X-Script-Name
(for security).

=head2 Example

=head1 TODO

Check uri encoding sanity and safety
/ chomping canonically
Should REQUEST_URI be touched?
X-Traversal-Query-String

=head1 LICENSE

This software is licensed under the same terms as Perl itself.

=head1 AUTHOR

Brad Bowman

Feedback from Chris Prather (perigrin)

=head1 SEE ALSO

L<Plack::Middleware::ReverseProxy>

L<http://pythonpaste.org/wsgiproxy/> source for header names

=cut

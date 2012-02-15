package Plack::Middleware::ReverseProxyPath;

use strict;
use warnings;
use parent qw(Plack::Middleware);
our $VERSION = '0.01';

sub call {
    my $self = shift;
    my $env = shift;

    if (    $env->{'HTTP_X_SCRIPT_NAME'}
         || $env->{'HTTP_X_TRAVERSAL_PATH'} ) {

        my $x_script_name    = $env->{'HTTP_X_SCRIPT_NAME'}     || '';
        my $x_traversal_path = $env->{'HTTP_X_TRAVERSAL_PATH'}  || '';
        my $script_name      = $env->{SCRIPT_NAME};
        my $path_info        = $env->{PATH_INFO};

        # replace $script_name . $path_info prefix of $x_traversal_path
        # with $x_script_name
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

            $path_info =~ s/^\Q$x_traversal_path\E//
                or _throw_error(
                    "Fragment: $x_traversal_path\n" .
                    "is not a prefix of \n" .
                    "PATH_INFO: $path_info\n" .
                    " SCRIPT_NAME: $script_name\n" .
                    " HTTP_X_TRAVERSAL_PATH: $env->{HTTP_X_TRAVERSAL_PATH}\n" );
        }
        $env->{SCRIPT_NAME} = $script_name;
        $env->{PATH_INFO}   = $path_info;

        # don't touch REQUEST_URI, it will continue to refer to the original
    }

    $self->app->($env);
}

sub _throw_error {
    my ($message) = @_;
    die Plack::Util::inline_object(
        code => sub { 500 },
        as_string => sub { $message },
    );
}

1;

__END__

=head1 NAME

Plack::Middleware::ReverseProxyPath - adjust proxied env to match client-facing

=head1 SYNOPSIS

  # configure your

  # in your PSGI backend
  builder {
      enable_if { $_[0]->{REMOTE_ADDR} eq '127.0.0.1' }
          "Plack::Middleware::ReverseProxy";
      enable_if { $_[0]->{REMOTE_ADDR} eq '127.0.0.1' }
          "Plack::Middleware::ReverseProxyPath";

      # $req->base now is the client-facing url
      # so Urls, Set-Cookie, Location can work naively
      $app;
  };

=head1 DESCRIPTION

Plack::Middleware::ReverseProxyPath adjusts SCRIPT_NAME and PATH_INFO
based on headers from a reverse proxy so that it's inner app can pretend
there is no proxy there.  This is useful when you aren't proxying and
entire server, but only a deeper path.

It should be used with Plack::Middleware::ReverseProxy which does equivalent
adjustments to to scheme, host and port environment attributes.

=head2 Required Headers

In order for this middleware to perform the path adjustments,
you will need to configure your reverse proxy to send the following
headers as applicable:

=over 4

=item X-Script-Name

The front-end prefix being forwarded FROM.

The value of SCRIPT_NAME on the reverse proxy (which is not the request
path used on the backend).

=item X-Traversal-Path

The backend prefix being forwarded TO.

If you aren't forwarding to the root of a server, but to some
deeper path, this contains the deeper path portion. So if you
forward to http://localhost:8080/myapp, and there is a request for
/article/1, then the full path forwarded to will be
/myapp/article/1. X-Traversal-Path will contain /myapp.

=back

=head2 Logic

If there is either X-Traversal-Path or X-Script-Name:

  SCRIPT_NAME . PATH_INFO =~ s/^X-Traversal-Path/X-Script-Name/

The X-Traversal-Path prefix will be stripped from SCRIPT_NAME
(borrowing from PATH_INFO if anything is left over) and
SCRIPT_NAME will be prefixed with X-Script-Name.

In the absence of reverse proxy headers, leave SCRIPT_NAME and PATH_INFO alone.
This allows direct connections to the backend to function.
Also, leave REQUEST_URI alone with to old/original value.

Front-ends should clear client sent X-Traversal-Path and X-Script-Name
(for security)

=head2 Example

=head1 TODO

Check uri encoding sanity and safety

=head1 LICENSE

This software is licensed under the same terms as Perl itself.

=head1 AUTHOR

Brad Bowman

Feedback from Chris Prather (perigrin)

=head1 SEE ALSO

L<Plack::Middleware::ReverseProxy>

L<http://pythonpaste.org/wsgiproxy/> source for header names

=cut

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
                or die;
        } else {
            # $x_traversal_path is longer, borrow from path_info
            $x_traversal_path =~ s/^\Q$script_name\E//
                or die;
            $script_name = $x_script_name;
            $path_info =~ s/^\Q$x_traversal_path\E//
                or die;
        }
        $env->{SCRIPT_NAME} = $script_name;
        $env->{PATH_INFO}   = $path_info;

        # don't touch REQUEST_URI, it will continue to refer to the original
    }

    $self->app->($env);
}

1;

__END__

=head1 NAME

Plack::Middleware::ReverseProxyPath - adjust paths on backend to match frontend

=head1 SYNOPSIS

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
two headers:

=over 4

=item X-Forwarded-Script-Name

The value of SCRIPT_NAME on the reverse proxy (which is not the request
path used on the backend).

=item X-Traversal-Path

If you aren't forwarding to the root of a server, but to some
deeper path, this contains the deeper path portion. So if you
forward to http://localhost:8080/myapp, and there is a request for
/article/1, then the full path forwarded to will be
/myapp/article/1. X-Traversal-Path will contain /myapp.

=item X-Script-Name

Explicitly define what the SCRIPT_NAME for the backend should be

=back

=head2 Logic

In the absence of reverse proxy headers, leave SCRIPT_NAME and PATH_INFO alone.
This allows direct connections to the backend to function.

If there is either X-Traversal-Path or X-Script-Name:

  SCRIPT_NAME . PATH_INFO =~ s/^X-Traversal-Path/X-Script-Name/

    Where the substitution can span SCRIPT_NAME and PATH_INFO with
    part application to each?

    Where the X-Traversal-Path can span SCRIPT_NAME and PATH_INFO,
    but the whole of X-Script-Name will be prefixed to SCRIPT_NAME
    (ie PATH_INFO could have a segment removed)

Strip X-Traversal-Path from PATH_INFO

SCRIPT_NAME = X-Script-Name . SCRIPT_NAME

Front-end should clear client sent X-Traversal-Path and X-Script-Name
(for security)

=head1 TODO

Check uri encoding sanity and safety

=head1 LICENSE

This software is licensed under the same terms as Perl itself.

=head1 AUTHOR

Brad Bowman

=head1 SEE ALSO

L<Plack::Middleware::ReverseProxy>

L<http://pythonpaste.org/wsgiproxy/> source for header names

=cut

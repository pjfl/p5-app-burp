package App::Burp::Watcher;

use namespace::autoclean;

use App::Burp; our $VERSION = $App::Burp::VERSION;

use Class::Usul::Constants qw( EXCEPTION_CLASS FALSE NUL OK SPC TRUE );
use Class::Usul::Functions qw( get_user io throw );
use Class::Usul::Types     qw( ArrayRef HashRef NonEmptySimpleStr
                               Object PositiveInt RegexpRef );
use Daemon::Control;
use English                qw( -no_match_vars );
use File::ChangeNotify;
use File::DataClass::Types qw( Path );
use Scalar::Util           qw( blessed );
use Unexpected::Functions  qw( Unspecified );
use Moo;

extends q(Class::Usul::Programs);

# Private methods
my $_daemon = sub {
   my $self = shift; my $mtimes = {};

   $PROGRAM_NAME = $self->_program_name.SPC.io( '.' )->parent->basename;

   $self->config->appclass->env_var( 'debug', $self->debug );

   while (my @events = $self->watcher->wait_for_events) {
      for my $event (@events) {
         my $path = io( $event->path ); my $file = $path->basename;

         $file =~ $self->config->excludes and next;

         my $mtime = $path->stat->{mtime};

         exists $mtimes->{ $file } and $mtimes->{ $file } == $mtime and next;

         my $cmd = [ split m{ [ ] }mx, $self->commands->{ $path->dirname } ];

         $self->run_cmd( $cmd, { out => 'stdout', err => 'stderr' } );

         $mtimes->{ $file } = $mtime;
      }
   }

   exit OK;
};

# Attribute constructors
my $_stdio_file = sub {
   my ($self, $extn, $name) = @_; $name //= $self->_program_name;

   return $self->file->tempdir->catfile( "${name}.${extn}" );
};

my $_build_daemon_control = sub {
   my $self = shift; my $conf = $self->config;

   my $prog = $conf->binsdir->catfile( $self->_program_name );
   my $args = {
      name         => blessed $self || $self,
      path         => $prog->pathname,

      directory    => $conf->appldir,
      program      => sub { shift; $self->$_daemon( @_ ) },
      program_args => [],

      pid_file     => $self->_pid_file->pathname,
      stderr_file  => $self->$_stdio_file( 'err' ),
      stdout_file  => $self->$_stdio_file( 'out' ),

      fork         => 2,
   };

   return Daemon::Control->new( $args );
};

my $_build_commands = sub {
   my $watchers = $_[ 0 ]->config->watchers;

   return { map   { io( $_ )->dirname, $watchers->{ $_ } }
            keys %{ $watchers } };
};

my $_build_directories = sub {
   return [ map { io( $_ )->dirname } keys %{ $_[ 0 ]->config->watchers } ];
};

my $_build_filter = sub {
   my $pattern = join '|', map   { io( $_ )->basename }
                           keys %{ $_[ 0 ]->config->watchers };

   return qr{ \A (?: $pattern ) \z }mx;
};

# Public attributes
# Override default in base class
has '+config_class' => default => 'App::Burp::Config';

has 'commands' => is => 'lazy', isa => HashRef[NonEmptySimpleStr],
   builder => $_build_commands;

has 'directories' => is => 'lazy', isa => ArrayRef[NonEmptySimpleStr],
   builder => $_build_directories;

has 'filter' => is => 'lazy', isa => RegexpRef, builder => $_build_filter;

has 'watcher' => is => 'lazy', isa => Object, builder => sub {
   File::ChangeNotify->instantiate_watcher
      ( directories => $_[ 0 ]->directories, filter => $_[ 0 ]->filter );
   };

# Private attributes
has '_daemon_control' => is => 'lazy', isa => Object,
   builder => $_build_daemon_control;

has '_daemon_pid' => is => 'lazy', isa => PositiveInt, builder => sub {
   my $path = $_[ 0 ]->_pid_file;

   return (($path->exists && !$path->empty ? $path->getline : 0) // 0) },
   clearer => TRUE;

has '_pid_file' => is => 'lazy', isa => Path, builder => sub {
   my $file = $_[ 0 ]->config->name.'.pid';

   return $_[ 0 ]->config->rundir->catfile( $file )->chomp
   };

has '_program_name' => is => 'lazy', isa => NonEmptySimpleStr,
   builder => sub { $_[ 0 ]->config->name };

# Construction
around 'run' => sub {
   my ($orig, $self) = @_; my $daemon = $self->_daemon_control;

   $daemon->name     or throw Unspecified, [ 'name'     ];
   $daemon->program  or throw Unspecified, [ 'program'  ];
   $daemon->pid_file or throw Unspecified, [ 'pid file' ];

   $daemon->uid and not $daemon->gid
                and $daemon->gid( get_user( $daemon->uid )->gid );

   $self->quiet( TRUE );

   return $orig->( $self );
};

# Public methods
sub dump_self : method {
   my $self = shift; $self->directories; $self->filter;

   return $self->SUPER::dump_self;
}

sub is_running {
   return $_[ 0 ]->_daemon_control->pid_running ? TRUE : FALSE;
}

sub restart : method {
   my $self = shift; $self->params->{restart} = [ { expected_rv => 1 } ];

   $self->is_running and $self->stop;

   return $self->start;
}

sub show_warnings : method {
   $_[ 0 ]->_daemon_control->do_show_warnings; return OK;
}

sub start : method {
   my $self = shift; $self->params->{start} = [ { expected_rv => 1 } ];

   $self->is_running and throw 'Already running';

   my $name = $self->config->name;
   my $rv = $self->_daemon_control->do_start;

   return $rv;
}

sub status : method {
   my $self = shift; $self->params->{status} = [ { expected_rv => 3 } ];

   return $self->_daemon_control->do_status;
}

sub stop : method {
   my $self = shift; $self->params->{stop} = [ { expected_rv => 1 } ];

   $self->is_running or throw 'Not running'; my $name = $self->config->name;

   my $rv = $self->_daemon_control->do_stop; $self->_clear_daemon_pid;

   return $rv;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Burp::Watcher - One-line description of the modules purpose

=head1 Synopsis

   use App::Burp::Watcher;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head2 C<restart> - Restart the server

Restart the server

=head2 C<show_warnings> - Show server warnings

Show server warnings

=head2 C<start> - Start the server

Start the server

=head2 C<status> - Show the current server status

Show the current server status

=head2 C<stop> - Stop the server

Stop the server

=head1 Diagnostics

=head1 Dependencies

=over 3

=item L<Class::Usul>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module. Please report problems to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Burp.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 Author

Peter Flanigan, C<< <pjfl@cpan.org> >>

=head1 License and Copyright

Copyright (c) 2016 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:

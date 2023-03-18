package App::Burp::Watcher::Inotify;

use File::Find      qw( find );
use Linux::Inotify2 1.2;
use Types::Standard qw( Bool Int );
use Type::Utils     qw( class_type );
use Moo;

has 'is_blocking' => is => 'ro', isa => Bool, default => 1;

has '_inotify' =>
   is       => 'ro',
   isa      => class_type('Linux::Inotify2'),
   init_arg => undef,
   default  => sub {
      Linux::Inotify2->new
         or die "Cannot construct a Linux::Inotify2 object: $!";
   };

has '_mask' => is => 'lazy', isa => Int, default => sub {
   my $self = shift;
   my $mask = IN_MODIFY | IN_CREATE | IN_DELETE
            | IN_DELETE_SELF | IN_MOVE_SELF | IN_MOVED_TO;

   $mask |= IN_DONT_FOLLOW unless $self->follow_symlinks;
   $mask |= IN_ATTRIB if $self->modify_includes_file_attributes;

   return $mask;
};

with 'File::ChangeNotify::Watcher';

around 'new_events' => sub {
   my ($orig, $self, @args) = @_;

   $self->_inotify->blocking(0);

   return $orig->($self, @args);
};

# Public methods
sub BUILD {
   my $self = shift;

   $self->_inotify->blocking($self->is_blocking);

   $self->_watch_files_and_directory($_) for @{$self->directories};

   $self->_set_map($self->_current_map)
      if $self->modify_includes_file_attributes
      || $self->modify_includes_content;

   return;
}

sub sees_all_events {1}

sub wait_for_events {
   my $self = shift;

   $self->_inotify->blocking(1);

   while (1) {
      my @events = $self->_interesting_events;
      return @events if @events;
   }
}

# Private methods
sub _add_watch_file_or_dir {
    my ($self, $path) = @_;

    return if $self->_path_is_excluded($path);
    return if -l $path && !$self->follow_symlinks;

    if (-d $path) {
       die "Failed to created directory watcher for ${path}"
          unless $self->_inotify->watch($path, $self->_mask);
    }
    elsif (-f $path) {
       my $mask = IN_MODIFY | IN_ATTRIB;

       die "Failed to created file watcher for ${path}"
          unless $self->_inotify->watch($path, $mask);
    }

    return;
}

sub _convert_event {
   my ($self, $event, $old_map, $new_map) = @_;

   my $path = $event->fullname;
   my $type
      = $event->IN_CREATE || $event->IN_MOVED_TO ? 'create'
      : $event->IN_MODIFY || $event->IN_ATTRIB   ? 'modify'
      : $event->IN_DELETE ? 'delete'
      :                     'unknown';
   my @extra;

   if ($type eq 'modify' && ($self->modify_includes_file_attributes
                             || $self->modify_includes_content)) {
      @extra = (
         $self->_modify_event_maybe_file_attribute_changes(
            $path, $old_map, $new_map
         ),
         $self->_modify_event_maybe_content_changes(
            $path, $old_map, $new_map
         ),
      );
   }

   return $self->event_class->new(path => $path, type => $type, @extra);
}

sub _fake_events_for_new_dir {
   my ($self, $dir) = @_;

   return unless -d $dir;

   my @events;

   File::Find::find({
      wanted => sub {
         my $path = $File::Find::name;

         return if $path eq $dir;

         if ($self->_path_is_excluded($path)) {
            $File::Find::prune = 1;
            return;
         }

         push @events, $self->event_class->new(path => $path, type => 'create');
      },
      follow_fast => ($self->follow_symlinks ? 1 : 0),
      no_chdir    => 1
   }, $dir);

   return @events;
}

sub _interesting_events {
   my $self   = shift;
   my @events = $self->_inotify->read;
   my ($old_map, $new_map);

   if (   $self->modify_includes_file_attributes
       || $self->modify_includes_content ) {
      $old_map = $self->_map;
      $new_map = $self->_current_map;
   }

   my $filter = $self->filter;
   my @interesting;

   for my $event (@events) {
      next if $self->_path_is_excluded($event->fullname);

      if ($event->IN_CREATE && $event->IN_ISDIR) {
         $self->_watch_files_and_directory($event->fullname);
         push @interesting, $event;
         push @interesting, $self->_fake_events_for_new_dir($event->fullname);
      }
      elsif ($event->IN_DELETE_SELF) {
         $self->_remove_directory($event->fullname);
      }
      elsif ($event->IN_ATTRIB) {
         next unless $self->_path_matches(
            $self->modify_includes_file_attributes, $event->fullname
         );
         push @interesting, $event;
      }
      elsif ($event->fullname =~ m{ $filter }mx) {
         push @interesting, $event;
      }
   }

   $self->_set_map($new_map) if $self->_has_map;

   return map {
      $_->can('path') ? $_ : $self->_convert_event($_, $old_map, $new_map)
   } @interesting;
}

sub _watch_files_and_directory {
   my ($self, $dir) = @_;

   return unless -d $dir;

   find({
      wanted => sub {
         my $path = $File::Find::name;

         if ($self->_path_is_excluded($path)) {
            $File::Find::prune = 1;
            return;
         }
         $self->_add_watch_file_or_dir($path);
      },
      follow_fast => ($self->follow_symlinks ? 1 : 0),
      no_chdir    => 1,
      follow_skip => 2,
   }, $dir);
}

use namespace::autoclean;

1;

package AI::MXNet::Callback;
use strict;
use warnings;
use List::Util qw/max/;
use AI::MXNet::Function::Parameters;
use Mouse;
use overload "&{}" => sub { my $self = shift; sub { $self->call(@_) } };

=head1 NAME

AI::MXNet::Callback - A collection of predefined callback functions
=cut

=head2 module_checkpoint

Callback to checkpoint Module to prefix every epoch.

Parameters
----------
$mod : subclass of AI::MXNet::Module::Base
    The module to checkpoint.
$prefix : str
    The file prefix to checkpoint to
$period=1 : int
    How many epochs to wait before checkpointing. Default is 1.
$save_optimizer_states=0 : Bool
    Whether to save optimizer states for continue training

Returns
-------
$callback : sub ref
    The callback function that can be passed as iter_end_callback to fit.
=cut

method module_checkpoint(
    AI::MXNet::Module::Base $mod,
    Str $prefix,
    Int $period=1,
    Int $save_optimizer_states=0
)
{
    $period = max(1, $period);
    return sub {
        my ($iter_no, $sym, $arg, $aux) = @_;
        if(($iter_no + 1) % $period == 0)
        {
            $mod->save_checkpoint($prefix, $iter_no + 1, $save_optimizer_states);
        }
    }
}

=head2 log_train_metric

Callback to log the training evaluation result every period.

Parameters
----------
$period : Int
    The number of batch to log the training evaluation metric.
$auto_reset : Bool
    Reset the metric after each log

Returns
-------
$callback : sub ref
    The callback function that can be passed as iter_epoch_callback to fit.
=cut

method log_train_metric(Int $period, Int $auto_reset=0)
{
    return sub {
        my ($param) = @_;
        if($param->nbatch % $period == 0 and defined $param->eval_metric)
        {
            my $name_value = $param->eval_metric->get_name_value;
            while(my ($name, $value) = each %{ $name_value })
            {
                AI::MXNet::Logging->info(
                    "Iter[%d] Batch[%d] Train-%s=%f",
                    $param->epoch, $param->nbatch, $name, $value
                );
            }
            $param->eval_metric->reset if $auto_reset;
        }
    }
}

package AI::MXNet::Speedometer;
use Mouse;
use Time::HiRes qw/time/;
extends 'AI::MXNet::Callback';

=head1 NAME

AI::MXNet::Speedometer - A callback that logs training speed 
=cut

=head1 DESCRIPTION

Calculate and log training speed periodically.

    Parameters
    ----------
    batch_size: int
        batch_size of data
    frequent: int
        How many batches between calculations.
        Defaults to calculating & logging every 50 batches.
=cut

has 'batch_size' => (is => 'ro', isa => 'Int', required => 1);
has 'frequent'   => (is => 'ro', isa => 'Int', default  => 50);
has 'init'       => (is => 'rw', isa => 'Int', default  => 0);
has 'tic'        => (is => 'rw', isa => 'Num', default  => 0);
has 'last_count' => (is => 'rw', isa => 'Int', default  => 0);

method call(AI::MXNet::BatchEndParam $param)
{
    my $count = $param->nbatch;
    if($self->last_count > $count)
    {
        $self->init(0);
    }
    $self->last_count($count);

    if($self->init)
    {
        if(($count % $self->frequent) == 0)
        {
            my $speed = $self->frequent * $self->batch_size / (time - $self->tic);
            if(defined $param->eval_metric)
            {
                my $name_value = $param->eval_metric->get_name_value;
                $param->eval_metric->reset;
                while(my ($name, $value) = each %{ $name_value })
                {
                    AI::MXNet::Logging->info(
                        "Epoch[%d] Batch [%d]\tSpeed: %.2f samples/sec\tTrain-%s=%f",
                        $param->epoch, $count, $speed, $name, $value
                    );
                }
            }
            else
            {
                AI::MXNet::Logging->info(
                    "Iter[%d] Batch [%d]\tSpeed: %.2f samples/sec",
                    $param->epoch, $count, $speed
                );
            }
            $self->tic(time);
        }
    }
    else
    {
        $self->init(1);
        $self->tic(time);
    }
}

*slice = \&call;

package AI::MXNet::ProgressBar;
use Mouse;
extends 'AI::MXNet::Callback';

=head1 NAME

AI::MXNet::ProgressBar - A callback to show a progress bar.

=head1 DESCRIPTION

Show a progress bar.

Parameters
----------
total: Int
    total batch size, 1
length: Int
    length or progress bar, 80
=cut

has 'length'  => (is => 'ro', isa => 'Int', default => 80);
has 'total'   => (is => 'ro', isa => 'Int', required => 1);

method call(AI::MXNet::BatchEndParam $param)
{
    my $count = $param->nbatch;
    my $filled_len = int(0.5 + $self->length * $count / $self->total);
    my $percents = int(100.0 * $count / $self->total) + 1;
    my $prog_bar = ('=' x $filled_len) . ('-' x ($self->length - $filled_len));
    print "[$prog_bar] $percents%\r";
}

*slice = \&call;

# Just logs the eval metrics at the end of an epoch.
package AI::MXNet::LogValidationMetricsCallback;
use Mouse;
extends 'AI::MXNet::Callback';

=head1 NAME

AI::MXNet::LogValidationMetricsCallback - A callback to log the eval metrics at the end of an epoch.
=cut

method call(AI::MXNet::BatchEndParam $param)
{
    return unless defined $param->eval_metric;
    my $name_value = $param->eval_metric->get_name_value;
    while(my ($name, $value) = each %{ $name_value })
    {
        AI::MXNet::Logging->info(
            "Epoch[%d] Validation-%s=%f",
            $param->epoch, $name, $value
        );
    }
}

package AI::MXNet::Callback;

method Speedometer()
{
    AI::MXNet::Speedometer->new(
        @_ == 2 ? (batch_size => $_[0], frequent => $_[1]) : (batch_size => $_[0])
    )
}

method ProgressBar()
{
    AI::MXNet::ProgressBar->new(
        @_ == 2 ? (total => $_[0], 'length' => $_[1]) : (total => $_[0])
    )
}

method LogValidationMetricsCallback()
{
    AI::MXNet::LogValidationMetricsCallback->new
}

1;
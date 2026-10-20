# steps x0 y0 x1 y1 n flag : emit n drag events from p0 to p1
steps() { local x0=$1 y0=$2 x1=$3 y1=$4 n=$5 fl=${6:-}; for i in $(seq 1 $n); do
  x=$(( x0 + (x1-x0)*i/n )); y=$(( y0 + (y1-y0)*i/n )); ./evt drag $x $y $fl; sleep 0.02; done; }

//TODO: go over this. 
def solve[n:!ℕ](x:𝔹^n, y:𝔹)lifted{
    for half_p in [1..((n-1) div 2)]{
        for k in [0..(2*half_p)..n-1]{
            for j in [0..half_p-1]{
                x[k + j] := X[k + j];
            }
        }
        if (x == vector(n,1:!𝔹)){
            y := X(y);
        }
        if (x == vector(n,0:!𝔹)){
            y := X(y);
        }
        for k in [0..(2*half_p)..n-1]{
            for j in [0..half_p-1]{
                x[k + j] := X[k + j];
            }
        }
    }
    return (x, y);
}
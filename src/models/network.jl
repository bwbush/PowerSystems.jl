export Branch
export Line
export Transformer2W
export Transformer3W
export Network

abstract type 
    Branch
end

struct Line <: Branch
    name::String
    status::Bool
    connectionpoints::Tuple{Bus,Bus}
    r::Float64 #[pu]
    x::Float64 #[pu]Co
    b::Float64 #[pu]
    rate::Nullable{Float64}  #[MVA]
    anglelimits::Nullable{Tuple{Float64,Float64}}
end

Line(;  name = "init",
        status = false,
        connectionpoints = (Bus(), Bus()),
        r = 0.0,
        x = 0.0,
        b = 0.0, 
        rate = Nullable{Float64}(),
        anglelimits = Nullable{Tuple{Float64,Float64}}()
    ) = Line(name, status, connectionpoints, r, x, b, rate, anglelimits)

"""
The 2-W transformer model uses an equivalent circuit assuming the impedance is on the High Voltage Side of the transformer. 
The model allocates the iron losses and magnetezing suceptance to the primary side 
"""

struct Transformer2W <: Branch
    name::String
    status::Bool
    connectionpoints::Tuple{Bus,Bus}    
    r::Float64 #[pu]
    x::Float64 #[pu]
    zb::Float64 #[pu]
    tap::Float64 # [0 - 2]
    α::Float64 # [radians]
    rate::Nullable{Float64}  #[MVA]
end

Transformer2W(; name = "init",
                status = false,
                connectionpoints = (Bus(), Bus()),
                r = 0.0,
                x = 0.0,
                zb = 0.0, 
                tap = 1.0,
                α = 0.0,
                rate = Nullable{Float64}()
            ) = Transformer2W(name, status, connectionpoints, r, x, zb, tap, α, rate)

struct Transformer3W <: Branch
    name::String
    status::Bool
    transformer::Transformer2W   
    line::Line
end

Transformer3W(; name = "init",
                status = false,
                transformer = Transformer2W(),
                line = Line()
            ) = Transformer3W(name, status, transformer, line)

function build_ybus(sys::SystemParam, branches::Array{T}) where {T<:Branch}

    Ybus = spzeros(Complex{Float64},sys.busquantity,sys.busquantity)
       
    for b in branches

        if b.name == "init" 
            error("The data in Branch is incomplete")
        end

        if typeof(b) == PowerSchema.Line

            Y11 = (1/(b.r + b.x*1im) + (1im*b.b)/2)*b.status;
            Ybus[b.connectionpoints[1].number,
                b.connectionpoints[1].number] += Y11;
            Y12 = (-1./(b.r + b.x*1im))*b.status;
            Ybus[b.connectionpoints[1].number, 
                b.connectionpoints[2].number] += Y12;
            #Y21 = Y12
            Ybus[b.connectionpoints[2].number, 
                b.connectionpoints[1].number] += Y12;
            #Y22 = Y11;
            Ybus[b.connectionpoints[2].number,
                b.connectionpoints[2].number] += Y11;    
      
        end

        if typeof(b) == PowerSchema.Transformer2W 

            y = 1/(b.r + b.x*1im)
            y_a = y/(b.tap*exp(b.α*1im*(π/180)))
            c = 1/b.tap

            Y11 = (y_a + y*c*(c-1) + (b.zb))*b.status;
            Ybus[b.connectionpoints[1].number,
                b.connectionpoints[1].number] += Y11;
            Y12 = (-y_a) * b.status;
            Ybus[b.connectionpoints[1].number, 
                b.connectionpoints[2].number] += Y12;
            #Y21 = Y12
            Ybus[b.connectionpoints[2].number, 
                b.connectionpoints[1].number] += Y12;
            Y22 = (y_a + y*(1-c)) * b.status;;
            Ybus[b.connectionpoints[2].number,
                b.connectionpoints[2].number] += Y22;    

        end

        if typeof(b) == PowerSchema.Transformer3W 

            warn("Data contains a 3W transformer")

            Y11 = (1/(b.line.r + b.line.x*1im) + (1im*b.line.b)/2)*b.status;
            Ybus[b.line.connectionpoints[1].number,
                b.line.connectionpoints[1].number] += Y11;
            Y12 = (-1./(b.line.r + b.line.x*1im))*b.status;
            Ybus[b.line.connectionpoints[1].number, 
                b.line.connectionpoints[2].number] += Y12;
            #Y21 = Y12
            Ybus[b.line.connectionpoints[2].number, 
                b.line.onnectionpoints[1].number] += Y12;
            #Y22 = Y11;
            Ybus[b.line.connectionpoints[2].number,
                b.line.connectionpoints[2].number] += Y11; 
                
            y = 1/(b.transformer.r + b.transformer.x*1im)
            y_a = y/(b.transformer.tap*exp(b.transformer.α*1im*(π/180)))
            c = 1/b.transformer.tap

            Y11 = (y_a + y*c*(c-1) + (b.transformer.zb))*b.status;
            Ybus[b.transformer.connectionpoints[1].number,
                b.transformer.connectionpoints[1].number] += Y11;
            Y12 = (-y_a) * b.status;
            Ybus[b.transformer.connectionpoints[1].number, 
                b.transformer.connectionpoints[2].number] += Y12;
            #Y21 = Y12
            Ybus[b.transformer.connectionpoints[2].number, 
                b.transformer.connectionpoints[1].number] += Y12;
            Y22 = (y_a + y*(1-c)) * b.status;;
            Ybus[b.transformer.connectionpoints[2].number,
                b.transformer.connectionpoints[2].number] += Y22;            
            
        end

    end

    return Ybus

end 

function build_ptdf(sys::SystemParam, branches::Array{T}, nodes::Array{Bus}) where {T<:Branch}

    n_b = length(branches)
    
    n_n = sys.busquantity;

    max_flows = Array{Float64}(length(branches))

    for b in nodes
        if b.number < -1
            error("buses must be numbered consecutively in the bus/node matrix")
        end
    end

    A = spzeros(Float64,n_n,n_b);
    B = spzeros(Float64,n_n,n_n);
    X = spzeros(Float64,n_b,n_b);

   #build incidence matrix 
   #incidence_matrix = A

    for (ix,b) in enumerate(branches)

        A[b.connectionpoints[1].number, ix] =  1;

        A[b.connectionpoints[2].number, ix] = -1;

        if typeof(b) == PowerSchema.Transformer2W 

            Y11 = (1/(b.tap*b.x))*b.status;
            X[ix,ix] = b.x*b.tap;

        elseif typeof(b) == PowerSchema.Line

            Y11 = (1/b.x)*b.status;
            X[ix,ix] = b.x;

        elseif typeof(b) == PowerSchema.Transformer3W 

            error("3W Transformer not implemented about PTDF")

        end

        B[b.connectionpoints[1].number,
            b.connectionpoints[1].number] += Y11;
        Y12 = -1*Y11;
        B[b.connectionpoints[1].number, 
            b.connectionpoints[2].number] += Y12;
        #Y21 = Y1
        B[b.connectionpoints[2].number, 
            b.connectionpoints[1].number] += Y12;
        #Y22 = Y11;
        B[b.connectionpoints[2].number,
            b.connectionpoints[2].number] += Y11;

        max_flows[ix] = get(b.rate)     
    end

    slack_position = -9; 

    for n in nodes
        if get(n.bustype) == "SF"
            slack_position = n.number
        end
    end

    if slack_position != -9 
        B = B[setdiff(1:end, slack_position), setdiff(1:end, slack_position)]

        S = inv(full(X))*A[setdiff(1:end, slack_position), :]'*inv(full(B));
        
        S = hcat(S[:,1:slack_position-1],zeros(n_b,),S[:,slack_position:end-1])

    elseif slack_position == -9 
        
        warn("Slack bus not identified in the Bus/Nodes list, can't build PTLDF")
        S = Nullable{Array{Float64}}()

    end

    return S, A, max_flows

end

struct Network 
    linequantity::Int
    ybus::SparseMatrixCSC{Complex{Float64},Int64}
    ptdf::Nullable{Array{Float64}}
    incidence::Nullable{Array{Int}}
    maxflows::Array{Float64} 

    function Network(sys::SystemParam, branches::Array{T}, nodes::Array{Bus}) where {T<:Branch}
        
        for n in nodes
            if isnull(n.bustype) 
                error("Bus/Nodes data does not contain information to build an AC network")
            end
        end
        
        ybus = build_ybus(sys,branches);
        ptdf, A, maxflow = build_ptdf(sys, branches, nodes)    
        new(length(branches),
            ybus, 
            ptdf,
            A,
            maxflow)
    end

end

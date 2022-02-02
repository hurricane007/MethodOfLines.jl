function _boundary_rules(s, orders, x, val)
    #TODO: Change this around to detect boundary variables anywhere in the eq
   args = copy(s.params)

    args = substitute.(args, (x=>val,))

    rules = [operation(u)(args...) => [operation(u)(args...), x] for u in s.ū]

    return vcat(rules, vec([(Differential(x)^d)(operation(u)(args...)) => [operation(u)(args...), x] for d in orders[x], u in s.ū]))
end

function generate_boundary_matching_rules(s, orders)
    # TODO: Check for bc equations of multiple variables
    lowerboundary(x) = first(s.axies[x])
    upperboundary(x) = last(s.axies[x])

    # Rules to match boundary conditions on the lower boundaries
    lower = reduce(vcat, [_boundary_rules(s, orders, x, lowerboundary(x)) for x in s.x̄])

    upper = reduce(vcat, [_boundary_rules(s, orders, x, upperboundary(x)) for x in s.x̄])

    return (lower, upper)
end


#---- Count Boundary Equations --------------------
# Count the number of boundary equations that lie at the spatial boundary on
# both the left and right side. This will be used to determine number of
# interior equations s.t. we have a balanced system of equations.

# get the depvar boundary terms for given depvar and indvar index.
get_depvarbcs(u, s, i) = substitute.((u,), get_edgevals(s, i))

# return the counts of the boundary-conditions that reference the "left" and
# "right" edges of the given independent variable. Note that we return the
# max of the count for each depvar in the system of equations.
@inline function get_bc_counts(i, s, bcs)
    left = 0
    right = 0
    for u in s.ū
        depvaredges = get_depvarbcs(u, s, i)
        counts = [map(u -> occursin(u, bc.lhs), depvaredges) for bc in bcs]
        left = max(left, sum([c[1] for c in counts]))
        right = max(right, sum([c[2] for c in counts]))
    end
    return [left, right]
end


"""
Mutates bceqs and u0 by finding relevant equations and discretizing them.
TODO: return a handler for use with generate_finite_difference_rules and pull out initial condition. Important to remember that BCs can have 
"""
function BoundaryHandler!!(u0, bceqs, bcs, s::DiscreteSpace, depvar_ops, tspan, derivweights::DifferentialDiscretizer) 
    
    t=s.time
    
    if t === nothing
        initmaps = s.ū
    else
        initmaps = substitute.(s.ū,[t=>tspan[1]])
    end

    # Create some rules to match which bundary/variable a bc concerns
    # * Assume that the term of the condition is applied additively and has no multiplier/divisor/power etc.
    
    ## BC matching rules, returns the variable and parameter the bc concerns

    lower_boundary_rules, upper_boundary_rules = generate_boundary_matching_rules(s, derivweights.orders)

    # indexes for Iedge depending on boundary type
    idx(::LowerBoundary) = 1
    idx(::UpperBoundary) = 2
    Iedge = edges(s)
    # Generate initial conditions and bc equations
    for bc in bcs
        # * Assume in the form `u(...) ~ ...` for now
        bcdepvar = first(get_depvars(bc.lhs, depvar_ops))
        
        if any(u -> isequal(operation(u), operation(bcdepvar)), s.ū)
            if t !== nothing && operation(bc.lhs) isa Sym && !any(x -> isequal(x, t.val), arguments(bc.lhs))
                # initial condition
                # * Assume that the initial condition is not in terms of the initial derivative
                initindex = findfirst(isequal(bc.lhs), initmaps) 
                if initindex !== nothing
                    push!(u0,vec(s.discvars[s.ū[initindex]] .=> substitute.((bc.rhs,),gridvals(s))))
                end
            else
                # Split out additive terms
                terms = split_additive_terms(bc)

                u_, x_ = (nothing, nothing)
                boundary = nothing
                # Check whether the bc is on the lower boundary, or periodic
                for term in terms, r in lower_boundary_rules
                    #Check if the rule changes the expression
                    if subsmatch(term, r)
                        # Get the matched variables from the rule
                        u_, x_ = r.second
                        # Mark the boundary                        
                        boundary = LowerBoundary()
                        # for term_ in setdiff(terms, term)
                        #     for r_ in upper_boundary_rules
                        #         if subsmatch(term_, r_) !== nothing
                        #             boundary = PeriodicBoundary()
                        #             #TODO: Add handling for perioodic boundary conditions here
                        #         end
                        #     end
                        # end
                        break
                    end
                end
                for term in terms, r in upper_boundary_rules
                    if subsmatch(term, r)
                        u_, x_ = r.second 
                        boundary = UpperBoundary()
                        break
                    end
                end

                @assert boundary !== nothing "Boundary condition $bc is not on a boundary of the domain, or is not a valid boundary condition"
                push!(bceqs, vec(map(Iedge[x_][idx(boundary)]) do II
                    rules = generate_bc_rules(II, derivweights, s, bc, u_, x_, boundary)
                    
                    substitute(bc.lhs, rules) ~ substitute(bc.rhs, rules)
                end))
            end
        end
    end
    push!(bceqs, cornereqs(s))
end

function generate_bc_rules(II, derivweights, s::DiscreteSpace{N,M,G}, bc, u_, x_, ::AbstractTruncatingBoundary) where {N, M, G<:CenterAlignedGrid}
    # depvarbcmaps will dictate what to replace the variable terms with in the bcs
    # replace u(t,0) with u₁, etc
    ufunc(v, I, x) = s.discvars[v][I]

    depvarderivbcmaps = []
    depvarbcmaps = []
    
    # * Assume that the BC is in terms of an explicit expression, not containing references to variables other than u_ at the boundary
    for u in s.ū
        if isequal(operation(u), operation(u_))
            # What to replace derivatives at the boundary with
            depvarderivbcmaps = [(Differential(x_)^d)(u_) => central_difference(derivweights.map[Differential(x_)^d], II, s, (s.x2i[x_], x_), u, ufunc) for d in derivweights.orders[x_]]
            # ? Does this need to be done for all variables at the boundary?
            depvarbcmaps = [u_ => s.discvars[u][II]]
            break
        end
    end
    fd_rules = generate_finite_difference_rules(II, s, bc, derivweights)
    varrules = axiesvals(s, x_, II)

    # valrules should be caught by depvarbcmaps and varrules if the above assumption holds
    #valr = valrules(s, II)
    
    return vcat(depvarderivbcmaps, depvarbcmaps, fd_rules, varrules)
end

function generate_bc_rules(II, derivweights, s::DiscreteSpace{N,M,G}, bc, u_, x_, boundary::AbstractTruncatingBoundary) where {N, M, G<:EdgeAlignedGrid}
    
    ufunc(v, I, x) = s.discvars[v][I]

    depvarderivbcmaps = []
    depvarbcmaps = []

    # depvarbcmaps will dictate what to replace the variable terms with in the bcs
    # replace u(t,0) with u₁, etc
    # * Assume that the BC is in terms of an explicit expression, not containing references to variables other than u_ at the boundary
    j = s.x2i[x_]
    shift(::LowerBoundary) = zero(II)
    shift(::UpperBoundary) = unitindex(N, j)
    for u in s.ū
        if isequal(operation(u), operation(u_))
            depvarderivbcmaps = [(Differential(x_)^d)(u_) => half_offset_centered_difference(derivweights.halfoffsetmap[Differential(x_)^d], II-shift(boundary), s, (j,x_), u, ufunc) for d in derivweights.orders[x_]]
    
            depvarbcmaps = [u_ => half_offset_centered_difference(derivweights.interpmap[x_], II-shift(boundary), s, (j,x_), u, ufunc)]
            break
        end
    end
    
    fd_rules = generate_finite_difference_rules(II, s, bc, derivweights)
    varrules = axiesvals(s, x_, II)

    # valrules should be caught by depvarbcmaps and varrules if the above assumption holds
    #valr = valrules(s, II)
    
    return vcat(depvarderivbcmaps, depvarbcmaps, fd_rules, varrules)
end
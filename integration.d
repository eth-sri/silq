// Written in the D programming language
// License: http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0

import options, dexpr, util;
import std.conv;


MapX!(Q!(DExpr,DExpr),DExpr) definiteIntegralMemo;

DExpr definiteIntegral(DExpr expr,DExpr facts=one){
	auto t=q(expr,facts);
	if(t in definiteIntegralMemo) return definiteIntegralMemo[t];
	auto r=definiteIntegralImpl(t.expand);
	definiteIntegralMemo[t]=r;
	return r;
}

private DExpr definiteIntegralImpl(DExpr expr,DExpr facts=one){
	auto var=dDeBruijnVar(1);
	auto nexpr=expr.simplify(facts.incDeBruijnVar(1,0).simplify(one));
	if(expr != nexpr) expr=nexpr;
	if(expr == zero) return zero;
	auto ow=expr.splitMultAtVar(var);
	ow[0]=ow[0].incDeBruijnVar(-1,0).simplify(facts);
	if(ow[0] != one || ow[1] != expr){ // TODO: second disjunct should not to be necessary
		if(auto r=definiteIntegral(ow[1],facts)){
			return (ow[0]*r).simplify(facts);
		}
		return null;
	}
	/+foreach(f;expr.factors){
		if(auto case_=cast(DMCase)f){
			if(!case_.e.hasFreeVar(dDeBruijnVar(1))){
				auto val=case_.val.incDeBruijnVar(1,0).substitute(dDeBruijnVar(2),dDeBruijnVar(1)).incDeBruijnVar(-1,1);
				auto rest=expr.withoutFactor(f).incDeBruijnVar(1,1);
				auto vali=definiteIntegral(val*rest,facts);
				auto erri=definiteIntegral(case_.err*rest,facts);
				if(vali&&erri){
					auto e=case_.e.incDeBruijnVar(-1,0);
					return dMCase(e,vali,erri).simplify(facts);
				}
			}
		}
	}+/

	DExpr discDeltaSubstitution(){
		foreach(f;expr.factors){
			if(!f.hasFreeVar(var)) continue;
			if(auto d=cast(DDiscDelta)f){
				if(d.var == var && !d.e.hasFreeVar(var))
					return expr.withoutFactor(f).substitute(var,d.e).incDeBruijnVar(-1,0).simplify(facts);
				if(d.e == var) // TODO: more complex "inversions"?
					return expr.withoutFactor(f).substitute(var,d.var).incDeBruijnVar(-1,0).simplify(facts);
			}
		}
		return null;
	}
	if(auto r=discDeltaSubstitution())
		return r;
	DExpr deltaSubstitution(){
		// TODO: detect when to give up early?
		foreach(f;expr.factors){
			if(!f.hasFreeVar(var)) continue;
			if(auto d=cast(DDelta)f){
				if(auto r=DDelta.performSubstitution(d,expr.withoutFactor(f),false))
					return r.simplify(facts);
			}
		}
		return null;
	}
	if(auto r=deltaSubstitution()) return r;
	foreach(T;Seq!(DDiscDelta,DDelta,DIvr)){ // TODO: need to split on DIvr?
		foreach(f;expr.factors){
			if(auto p=cast(DPlus)f){
				bool check(){
					foreach(d;p.allOf!T(true))
						if(d.hasFreeVar(var))
							return true;
					return false;
				}
				if(check()){
					DExprSet works;
					DExprSet doesNotWork;
					bool simpler=false;
					foreach(k;distributeMult(p,expr.withoutFactor(f))){
						k=k.simplify(facts.incDeBruijnVar(1,0).simplify(one));
						auto ow=k.splitMultAtVar(var);
						ow[0]=ow[0].incDeBruijnVar(-1,0).simplify(facts);
						if(ow[0] == zero){ simpler=true; continue; }
						auto r=definiteIntegral(ow[1],facts);
						if(r){
							DPlus.insert(works,ow[0]*r);
							simpler=true;
						}else DPlus.insert(doesNotWork,k);
					}
					if(simpler){
						auto r=dPlus(works).simplify(facts);
						if(doesNotWork.length) r = r + dInt(dPlus(doesNotWork));
						return r;
					}
				}
			}
		}
	}
	nexpr=expr.linearizeConstraints!(x=>!!cast(DDelta)x)(var).simplify(facts.incDeBruijnVar(1,0).simplify(one)); // TODO: only linearize the first feasible delta.
	if(nexpr != expr) return definiteIntegral(nexpr,facts);
	/+if(auto r=deltaSubstitution(true))
	 return r;+/

	if(expr == one) return null; // (infinite integral)

	if(opt.integrationLevel!=IntegrationLevel.deltas){
		nexpr=expr.linearizeConstraints!(x=>!!cast(DIvr)x)(var).simplify(facts.incDeBruijnVar(1,0).simplify(one));
		if(nexpr != expr) return definiteIntegral(nexpr,facts);
		if(auto r=definiteIntegralContinuous(expr,facts))
			return r;
	}
	// pull sums out
	foreach(f;expr.factors){
		if(auto sum=cast(DSum)f){
			auto nexpr=sum.expr.incDeBruijnVar(1,0).substitute(dDeBruijnVar(3),dDeBruijnVar(1)).incDeBruijnVar(-1,2)*expr.withoutFactor(f).incDeBruijnVar(1,1);
			if(auto r=definiteIntegral(nexpr,facts.incDeBruijnVar(1,0).simplify(one)))
				return dSum(r).simplify(facts);
		}
	}
	// Fubini
	DExpr fubini(){
		bool hasInt=false;
		Q!(DExpr,int) fubiRec(DExpr cur){
			// TODO: execute incDeBruijnVar only once for each subexpression
			// (such that the running time is linear in the expression size)
			DExpr r=one;
			foreach(f;cur.factors)
				if(!cast(DInt)f)
					r=r*f;
			int numVars=0;
			foreach(f;cur.factors){
				if(auto other=cast(DInt)f){
					hasInt=true;
					auto en=fubiRec(other.expr);
					r=r.incDeBruijnVar(en[1],0);
					r=r*en[0].incDeBruijnVar(numVars,en[1]);
					numVars+=en[1];
				}
			}
			return q(r,numVars+1);
		}
		auto fubiExprNumVars=fubiRec(expr);
		if(!hasInt) return null;
		auto fubiExpr=fubiExprNumVars[0], numFubiVars=fubiExprNumVars[1];
		fubiExpr=fubiExpr.incDeBruijnVar(1,0).substitute(dDeBruijnVar(numFubiVars+1),dDeBruijnVar(1)).incDeBruijnVar(-1,numFubiVars);
		auto r=definiteIntegral(fubiExpr,facts.incDeBruijnVar(numFubiVars-1,0).simplify(one));
		if(!r) return null;
		foreach_reverse(v;0..numFubiVars-1) r=dInt(r);
		return r.simplify(facts);
	}
	assert(var == dDeBruijnVar(1));
	if(auto r=fubini()) return r;
	if(!expr.hasFreeVar(var)) return expr.incDeBruijnVar(-1,0)*dInt(one); // (infinite integral)
	return null;
}

bool isContinuousMeasureIn(DExpr expr,DVar var){
	if(!expr.hasFreeVar(var)) return true;
	if(auto d=cast(DDistApply)expr) return !d.arg.hasFreeVar(var);
	if(auto d=cast(DDelta)expr) return !d.e.hasFreeVar(var);
	if(auto d=cast(DDiscDelta)expr) return !d.var.hasFreeVar(var);
	if(cast(DIvr)expr||cast(DVar)expr||cast(DPow)expr||cast(DLog)expr||cast(DSin)expr||cast(DFloor)expr||cast(DCeil)expr||cast(DGaussInt)expr||cast(DAbs)expr)
		return true;
	if(auto p=cast(DPlus)expr){
		foreach(s;p.summands)
			if(!isContinuousMeasureIn(s,var))
				return false;
		return true;
	}
	if(auto m=cast(DMult)expr){
		foreach(f;m.factors)
			if(!isContinuousMeasureIn(f,var))
				return false;
		return true;
	}
	if(auto i=cast(DInt)expr) return isContinuousMeasureIn(i.expr,var.incDeBruijnVar(1,0));
	if(auto c=cast(DMCase)expr){
		if(!isContinuousMeasureIn(c.val,var.incDeBruijnVar(1,0))) return false;
		return isContinuousMeasureIn(c.err,var);
	}
	return false;
}


private DExpr definiteIntegralContinuous(DExpr expr,DExpr facts)out(res){
	version(INTEGRATION_STATS){
		integrations++;
		if(res) successfulIntegrations++;
	}
}body{
	// ensure integral is continuous
	auto var=dDeBruijnVar(1);
	if(!expr.isContinuousMeasureIn(var)) return null;
	if(auto r=tryIntegrate(expr))
		return r.simplify(facts);
	return null;
}

DExpr fromTo(DExpr anti,DVar var,DExpr lower,DExpr upper)in{
	assert(var==dDeBruijnVar(1));
}body{ // lower=null: lower=-∞. upper=0: upper=∞
	//dw(anti.substitute(var,lower).simplify(one)," ",lower," ",upper);
	auto lo=lower?unbind(anti,lower):null;
	auto up=upper?unbind(anti,upper):null;
	if(lower&&upper){
		//dw("??! ",dDiff(var,anti).simplify(one));
		//dw(anti.substitute(var,upper).simplify(one));
		//dw(anti.substitute(var,lower).simplify(one));
		return dIvr(DIvr.Type.leZ,lower-upper)*(up-lo);
	}
	if(!lo) lo=dLimSmp(var,-dInf,anti,one).incDeBruijnVar(-1,0);
	if(!up) up=dLimSmp(var,dInf,anti,one).incDeBruijnVar(-1,0);
	if(lo.isInfinite() || up.isInfinite()) return null;
	if(lo.hasLimits() || up.hasLimits()) return null;
	return up-lo;
}


DExpr tryGetAntiderivative(DExpr expr){
	auto var=dDeBruijnVar(1);
	auto ow=expr.splitMultAtVar(var);
	ow[0]=ow[0].simplify(one);
	if(ow[0] != one){
		if(auto rest=tryGetAntiderivative(ow[1].simplify(one)))
			return ow[0]*rest;
		return null;
	}
	auto lexpr=expr.linearizeConstraints(var).simplify(one);
	if(lexpr != expr) return tryGetAntiderivative(lexpr);
	foreach(ff;expr.factors){ // incorporate iverson brackets
		if(!cast(DIvr)ff) continue;
		auto ivrsNonIvrs=splitIvrsIntegral(expr);
		final switch(ivrsNonIvrs[0]) with(SplitIvrsIntegral){
			case fail: return null;
			case success: break;
			case zero: return .zero;
		}
		auto ivrs=ivrsNonIvrs[1][0].simplify(one),nonIvrs=ivrsNonIvrs[1][1].simplify(one);
		assert(ivrs&&nonIvrs);
		assert(ivrs.factors.all!(x=>x==one||cast(DIvr)x&&x.hasFreeVar(var)));
		auto loup=ivrs.getBoundsForVar(var);
		if(!loup[0]) return null;
		auto lower=loup[1][0],upper=loup[1][1];
		auto antid=tryGetAntiderivative(nonIvrs);
		if(!antid) return null;
		// TODO: handle the case where unbind(antid,lower) or unbind(antid,upper) are infinite properly
		// (this will 'just work' formally, but it is an ugly hack.)
		if(lower) antid=dIvr(DIvr.Type.leZ,var-lower)*(antid-unbind(antid,lower));
		if(upper) antid=dIvr(DIvr.Type.leZ,upper-var)*antid+dIvr(DIvr.Type.lZ,var-upper)*unbind(antid,upper);
		return antid.simplify(one);
	}
	static DExpr safeLog(DExpr e){ // TODO: integrating 1/x over 0 diverges (not a problem for integrals occurring in the analysis)
		return dLog(e)*dIvr(DIvr.Type.lZ,-e)
			+ dLog(-e)*dIvr(DIvr.Type.lZ,e);
	}
	if(auto p=cast(DPow)expr){
		if(!p.operands[1].hasFreeVar(var)){
			if(p.operands[0] == var){
				// constraint: lower && upper
				return (safeLog(var)*
				        dIvr(DIvr.Type.eqZ,p.operands[1]+1)
				        +(var^^(p.operands[1]+1))/(p.operands[1]+1)*
				        dIvr(DIvr.Type.neqZ,p.operands[1]+1)).simplify(one);
			}
			auto ba=p.operands[0].asLinearFunctionIn(var);
			auto b=ba[0],a=ba[1];
			if(a && b){
				return (dIvr(DIvr.Type.neqZ,a)*((safeLog(p.operands[0])*
				         dIvr(DIvr.Type.eqZ,p.operands[1]+1)
				         +(p.operands[0]^^(p.operands[1]+1))/(p.operands[1]+1)*
				          dIvr(DIvr.Type.neqZ,p.operands[1]+1))/a)
				        +dIvr(DIvr.Type.eqZ,a)*var*b^^p.operands[1]).simplify(one);
			}
		}
		if(!p.operands[0].hasFreeVar(var)){
			auto k=(safeLog(p.operands[0])*p.operands[1]).simplify(one);
			// need to integrate e^^(k(x)).
			auto ba=k.asLinearFunctionIn(var);
			auto b=ba[0],a=ba[1];
			if(a && b){
				assert(!a.hasFreeVar(var));
				return dIvr(DIvr.Type.neqZ,a)*dE^^k/a
					+ dIvr(DIvr.Type.eqZ,a)*var*dE^^b;
			}
		}
	}
	if(expr == one) return var; // constraint: lower && upper
	if(auto poly=expr.asPolynomialIn(var)){
		DExprSet s;
		foreach(i,coeff;poly.coefficients){
			assert(i<size_t.max);
			DPlus.insert(s,coeff*var^^(i+1)/(i+1));
		}
		// constraint: lower && upper
		return dPlus(s);
	}
	if(auto p=cast(DLog)expr){
		auto ba=p.e.asLinearFunctionIn(var);
		auto b=ba[0],a=ba[1];
		if(a && b){
			static DExpr logIntegral(DVar x,DExpr a, DExpr b){
				return (x+b/a)*safeLog(a*x+b)-x;
			}
			return dIvr(DIvr.Type.neqZ,a)*logIntegral(var,a,b)+
				dIvr(DIvr.Type.eqZ,a)*var*dLog(b);
		}
	}
	// integrate log(x)ʸ/x to log(x)ʸ⁺¹/(y+1)
	if(auto p=cast(DMult)expr){
		auto inv=1/var;
		if(p.hasFactor(inv)){
			auto without=p.withoutFactor(inv);
			DExpr y=null;
			// TODO: linear functions of var
			if(auto l=cast(DLog)without){
				if(l.e == var) y=one;
			}else if(auto pw=cast(DPow)without){
				if(auto l=cast(DLog)pw.operands[0])
					if(l.e == var) y=pw.operands[1];
			}
			if(y !is null && !y.hasFreeVar(var)){
				return dIvr(DIvr.Type.eqZ,y+1)*safeLog(safeLog(var))+
					dIvr(DIvr.Type.neqZ,y+1)*safeLog(var)^^(y+1)/(y+1);
			}
		}
	}
	// integrate log to some positive integer power
	if(auto p=cast(DPow)expr){
		if(auto l=cast(DLog)p.operands[0]){
			auto ba=l.e.asLinearFunctionIn(var);
			auto b=ba[0],a=ba[1];
			if(a && b){
				if(auto n=p.operands[1].isInteger()){
					DExpr dInGamma(DExpr a,DExpr z){
						a=a.incDeBruijnVar(1,0), z=z.incDeBruijnVar(1,0);
						auto t=dDeBruijnVar(1);
						return dIntSmp(t^^(a-1)*dE^^(-t)*dIvr(DIvr.type.leZ,z-t),one);
					}
					if(n.c>0)
						return dIvr(DIvr.Type.neqZ,a)*dIvr(DIvr.Type.neqZ,a*var+b)*mone^^n*dInGamma(n+1,-dLog(a*var+b))/a
							+ dIvr(DIvr.Type.eqZ,a)*var*dLog(b)^^n;
				}
			}
		}
	}
	DExpr gaussianIntegral(DVar v,DExpr e){
		// detect e^^(-a*x^^2+b*x+c), and integrate to e^^(b^^2/4a+c)*(pi/a)^^(1/2).
		// TODO: this currently assumes that a≥0. (The produced expressions are still formally correct if √(-1)=i)
		auto p=cast(DPow)e;
		if(!p||!cast(DE)p.operands[0]) return null;
		auto q=p.operands[1].asPolynomialIn(v,2);
		if(!q.initialized||q.degree!=2) return null;
		auto qc=q.coefficients;
		auto a=-qc.get(2,zero),b=qc.get(1,zero),c=qc.get(0,zero);
		// -a(x-b/2a)²=-ax²+bx-b²/4a
		// -ax²+bx+c =-a(x-b/2a)²+b²/4a+c
		// -ax²+bx+c =-(√(a)x-b/2√a)²+b²/4a+c
		// e^(-ax²+bx+c) = e^(b²/4a+c)·e^-(√(a)x-b/2√a)²
		// ∫dx e^(-ax²+bx+c)[l≤x≤r] = e^(b²/4a+c)·∫dx(e^-(√(a)x-b/(2√a))²[l≤x≤r]
		// = e^(b²/4a+c)·⅟√a∫dx(e^-x²)[l≤x/√(a)+b/(2a)≤r]
		// = e^(b²/4a+c)·⅟√a∫dx(e^-x²)[l*(√(a))-b/(2√(a))≤x≤r*(√(a))-b/(2√(a))]
		auto fac=dE^^(b^^2/(4*a)+c)*(one/a)^^(one/2);
		DExpr transform(DExpr x){
			if(x == dInf || x == -dInf) return x;
			auto sqrta=a^^(one/2);
			return sqrta*x-b/(2*sqrta);
		}
		// constraints: none!
		auto r=dIvr(DIvr.Type.neqZ,a)*fac*dGaussInt(transform(v));
		auto isZero=dIvr(DIvr.Type.eqZ,a).simplify(one);
		if(isZero!=zero){
			auto rest=tryGetAntiderivative(dE^^(b*v+c));
			if(!rest) return null;
			r=r+isZero*rest;
		}
		return r;
	}
	if(auto gauss=gaussianIntegral(var,expr)) return gauss;
	// TODO: this is just a list of special cases. Generalize!
	DExpr doubleGaussIntegral(DVar var,DExpr e){
		auto gi=cast(DGaussInt)e;
		if(!gi) return null;
		auto ba=gi.x.asLinearFunctionIn(var);
		auto b=ba[0],a=ba[1];
		if(a&&b){
			static DExpr primitive(DExpr e){
				if(e == -dInf) return zero;
				return dGaussInt(e)*e+dE^^(-e^^2)/2;
			}
			// constraints: upper
			return dIvr(DIvr.Type.neqZ,a)*primitive(gi.x)/a
				+ dIvr(DIvr.Type.eqZ,a)*var*dGaussInt(b);
		}
		return null;
	}
	if(auto dgauss=doubleGaussIntegral(var,expr)) return dgauss;
	DExpr gaussIntTimesGauss(DVar var,DExpr e){
		//∫dx (d/dx)⁻¹[e^(-x²)](g(x))·f(x) = (d/dx)⁻¹[e^(-x²)](g(x))·∫dx f(x) - ∫dx (g'(x)e^(-g(x)²)·∫dx f(x))
		auto m=cast(DMult)e;
		if(!m) return null;
		DGaussInt gaussFact=null;
		foreach(f;m.factors){
			if(auto g=cast(DGaussInt)f){
				gaussFact=g;
				break;
			}
		}
		if(!gaussFact) return null;
		auto rest=m.withoutFactor(gaussFact);
		auto gauss=dDiff(var,gaussFact).simplify(one);
		auto intRest=tryGetAntiderivative(rest);
		if(!intRest) return null;
		if(e == (gauss*intRest).simplify(one)){ // TODO: handle all cases
			return gaussFact*intRest/2;
		}
		return null;
	}
	if(auto dgaussTG=gaussIntTimesGauss(var,expr)) return dgaussTG;
	// partial integration for polynomials
	DExpr partiallyIntegratePolynomials(DVar var,DExpr e){ // TODO: is this well founded?
		static MapX!(Q!(DVar,DExpr),DExpr) memo;
		if(q(var,e) in memo) return memo[q(var,e)];
		auto token=freshVar("τ"); // TODO: make sure this does not create a GC issue.
		memo[q(var,e)]=token;
		auto fail(){
			memo[q(var,e)]=null;
			return null;
		}
		
		auto m=cast(DMult)e;
		if(!m) return fail();
		DExpr polyFact=null;
		foreach(f;m.factors){
			if(auto p=cast(DPow)f){
				if(p.operands[0] == var){
					if(auto c=p.operands[1].isInteger()){
						if(c.c>0){ polyFact=p; break; }
					}
				}
			}
			if(f == var){ polyFact=f; break; }
		}
		if(!polyFact) return fail();
		auto rest=m.withoutFactor(polyFact);
		auto intRest=tryGetAntiderivative(rest);
		if(!intRest) return fail();
		auto diffPoly=dDiff(var,polyFact);
		auto diffRest=(diffPoly*intRest).polyNormalize(var).simplify(one);
		auto intDiffPolyIntRest=tryGetAntiderivative(diffRest);
		if(!intDiffPolyIntRest) return fail();
		auto r=polyFact*intRest-intDiffPolyIntRest;
		if(!r.hasFreeVar(token)){ memo[q(var,e)]=r; return r; }
		if(auto s=(r-token).simplify(one).solveFor(token)){
			memo[q(var,e)]=s;
			return s;
		}
		return fail();
	}
	if(auto partPoly=partiallyIntegratePolynomials(var,expr)) return partPoly;

	// x = ∫ u'v
	// (uv)' = uv'+u'v
	// ∫(uv)' = ∫uv'+∫u'v
	// uv+C = ∫uv'+∫u'v
	// 
	//auto factors=splitIntegrableFactor(expr);
	//dw(factors[1]);
	//dw("!! ",dDiff(var,factors[1]));

	if(auto p=cast(DPlus)expr.polyNormalize(var).simplify(one)){
		DExpr r=zero;
		foreach(s;p.summands){
			auto a=tryGetAntiderivative(s);
			if(!a) return null;
			r=r+a;
		}
		return r;
	}
	return null; // no simpler expression available
}

MapX!(DExpr,DExpr) tryIntegrateMemo;

private DExpr tryIntegrate(DExpr expr){
	if(expr in tryIntegrateMemo) return tryIntegrateMemo[expr];
	auto r=tryIntegrateImpl(expr);
	tryIntegrateMemo[expr]=r;
	return r;
}

enum SplitIvrsIntegral{
	fail,
	success,
	zero
}
Q!(SplitIvrsIntegral,DExpr[2]) splitIvrsIntegral(DExpr expr){
	auto var=dDeBruijnVar(1);
	DExpr ivrs=one,nonIvrs=one;
	foreach(f;setx(expr.factors)){
		auto ivr=cast(DIvr)f;
		if(!ivr){ nonIvrs=nonIvrs*f; continue; }
		assert(!!ivr);
		if(ivr.type==DIvr.Type.eqZ||ivr.type==DIvr.Type.neqZ){
			bool mustHaveZerosOfMeasureZero(){
				auto e=ivr.e;
				if(e != e.linearizeConstraints(var)) return false; // TODO: guarantee this condition
				if(e.hasAny!DIvr) return false; // TODO: make sure this cannot actually happen
				if(e.hasAny!DFloor||e.hasAny!DCeil) return false;
				if(e.hasAny!DDistApply) return false; // TODO: some proofs still possible
				return true;
			}
			if(mustHaveZerosOfMeasureZero()){
				if(ivr.type==DIvr.Type.eqZ) return q(SplitIvrsIntegral.zero,(DExpr[2]).init);
				if(ivr.type==DIvr.Type.neqZ) continue;
			}else return q(SplitIvrsIntegral.fail,(DExpr[2]).init);
		}
		assert(ivr.type!=DIvr.Type.lZ);
		ivrs=ivrs*ivr;
	}
	return q(SplitIvrsIntegral.success,cast(DExpr[2])[ivrs,nonIvrs]);
}


private DExpr tryIntegrateImpl(DExpr expr){
	auto var=dDeBruijnVar(1);
	assert(expr.factors.all!(x=>!cast(DDelta)x));
	auto lexpr=expr.linearizeConstraints(var).simplify(one);
	if(lexpr != expr) return tryIntegrate(lexpr);
	auto ivrsNonIvrs=splitIvrsIntegral(expr);
	final switch(ivrsNonIvrs[0]) with(SplitIvrsIntegral){
		case fail: return null;
		case success: break;
		case zero: return .zero;
	}
	assert(ivrsNonIvrs[1][0]&&ivrsNonIvrs[1][1]);
	auto ivrs=ivrsNonIvrs[1][0].simplify(one);
	expr=ivrsNonIvrs[1][1].simplify(one);
	assert(ivrs==one||ivrs.factors.all!(x=>!!cast(DIvr)x));
	auto loup=ivrs.getBoundsForVar(var);
	if(!loup[0]) return null;
	DExpr lower=loup[1][0],upper=loup[1][1];
	// TODO: add better approach for antiderivatives	
	//dw(var," ",expr," ",ivrs);
	//dw(antid.antiderivative);
	//dw(dDiff(var,antid.antiderivative.simplify(one)).simplify(one));
	if(auto anti=tryGetAntiderivative(expr))
		return anti.fromTo(var,lower,upper);
	if(auto p=cast(DPlus)expr.polyNormalize(var)){
		DExprSet works;
		DExprSet doesNotWork;
		bool ok=true;
		foreach(s;p.summands){
			auto ow=s.splitMultAtVar(var);
			ow[0]=ow[0].incDeBruijnVar(-1,0).simplify(one);
			auto t=tryIntegrate(ow[1]);
			if(t) DPlus.insert(works,ow[0]*t);
			else DPlus.insert(doesNotWork,s);
		}
		if(works.length) return dPlus(works)+dInt((dPlus(doesNotWork)*ivrs));
	}//else dw("fail: ","Integrate[",expr.toString(Format.mathematica),",",var.toString(Format.mathematica),"]");
	return null; // no simpler expression available
}

function rec = damp_codes(rawCode, betaCode, Fr, Fb, Wb)
% Integer damper. Codes are the stored signed integers. A quantizes each
% product to S(16,10) before the sum. B rounds the aligned sum once.
Fs = max(Fr, Fb);
oldProd = 717 .* betaCode .* 2^(Fs - Fb);
newProd = 307 .* rawCode .* 2^(Fs - Fr);
[oldA, oldHit] = sat16(round(oldProd ./ 2^Fs));
[newA, newHit] = sat16(round(newProd ./ 2^Fs));
[rec.sumA, rec.sumSatA] = sat16(oldA + newA);
[rec.sumB, rec.sumSatB] = sat16(round((oldProd + newProd) ./ 2^Fs));
[rec.betaA, rec.writeSatA] = qbeta(rec.sumA, Fb, Wb);
[rec.betaB, rec.writeSatB] = qbeta(rec.sumB, Fb, Wb);
rec.prodOld = oldA;
rec.prodNew = newA;
rec.midSat = oldHit | newHit;
end

function [y, hit] = sat16(v)
lo = -32768;
hi = 32767;
hit = v < lo | v > hi;
y = min(hi, max(lo, v));
end

function [y, hit] = qbeta(code, Fb, Wb)
shift = 10 - Fb;
if shift >= 0
    y = round(code ./ 2^shift);
else
    y = code .* 2^(-shift);
end
lo = -2^(Wb - 1);
hi = 2^(Wb - 1) - 1;
hit = y < lo | y > hi;
y = min(hi, max(lo, y));
end

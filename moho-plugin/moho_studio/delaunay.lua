-- Pure Lua 5.4 Bowyer-Watson 2D Delaunay triangulation for live Smart Warp meshes.

local delaunay = {}

local function circumcircleContains(ax, ay, bx, by, cx, cy, px, py)
	local d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
	if math.abs(d) < 1e-12 then
		return false
	end
	local a2 = ax * ax + ay * ay
	local b2 = bx * bx + by * by
	local c2 = cx * cx + cy * cy
	local ux = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / d
	local uy = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / d
	local r2 = (ax - ux) * (ax - ux) + (ay - uy) * (ay - uy)
	local dist2 = (px - ux) * (px - ux) + (py - uy) * (py - uy)
	return dist2 <= r2 + 1e-10
end

local function edgeKey(a, b)
	if a < b then
		return a .. ":" .. b
	end
	return b .. ":" .. a
end

--- Triangulate a list of 2D points { {x=..., y=...}, ... }.
-- Returns list of 1-based index triples { {i, j, k}, ... }.
function delaunay.triangulate(pts)
	local n = #pts
	if n < 3 then
		return {}
	end

	local minX, maxX = pts[1].x, pts[1].x
	local minY, maxY = pts[1].y, pts[1].y
	for i = 2, n do
		if pts[i].x < minX then minX = pts[i].x end
		if pts[i].x > maxX then maxX = pts[i].x end
		if pts[i].y < minY then minY = pts[i].y end
		if pts[i].y > maxY then maxY = pts[i].y end
	end

	local dx = maxX - minX
	local dy = maxY - minY
	local delta = math.max(dx, dy, 1.0) * 10.0
	local midX = (minX + maxX) * 0.5
	local midY = (minY + maxY) * 0.5

	-- Super-triangle vertices appended at n+1, n+2, n+3
	local allPts = {}
	for i = 1, n do
		allPts[i] = pts[i]
	end
	local s1, s2, s3 = n + 1, n + 2, n + 3
	allPts[s1] = { x = midX - 2 * delta, y = midY - delta }
	allPts[s2] = { x = midX, y = midY + 2 * delta }
	allPts[s3] = { x = midX + 2 * delta, y = midY - delta }

	local triangles = { { s1, s2, s3 } }

	for pi = 1, n do
		local p = allPts[pi]
		local bad = {}
		local kept = {}
		for ti = 1, #triangles do
			local t = triangles[ti]
			local pa, pb, pc = allPts[t[1]], allPts[t[2]], allPts[t[3]]
			if circumcircleContains(pa.x, pa.y, pb.x, pb.y, pc.x, pc.y, p.x, p.y) then
				bad[#bad + 1] = t
			else
				kept[#kept + 1] = t
			end
		end

		local edgeCounts = {}
		local edgePairs = {}
		local function addEdge(a, b)
			local k = edgeKey(a, b)
			edgeCounts[k] = (edgeCounts[k] or 0) + 1
			edgePairs[k] = { a, b }
		end
		for bi = 1, #bad do
			local t = bad[bi]
			addEdge(t[1], t[2])
			addEdge(t[2], t[3])
			addEdge(t[3], t[1])
		end

		for k, count in pairs(edgeCounts) do
			if count == 1 then
				local e = edgePairs[k]
				kept[#kept + 1] = { e[1], e[2], pi }
			end
		end

		triangles = kept
	end

	-- Discard triangles touching super-triangle or degenerate collinear slivers
	local result = {}
	for ti = 1, #triangles do
		local t = triangles[ti]
		if t[1] <= n and t[2] <= n and t[3] <= n then
			local pa, pb, pc = allPts[t[1]], allPts[t[2]], allPts[t[3]]
			local area2 = math.abs((pb.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (pb.y - pa.y))
			if area2 > 1e-8 then
				result[#result + 1] = t
			end
		end
	end

	return result
end

return delaunay

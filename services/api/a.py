import requests


def brute_force_active_payloads(max_results=3):
	print("BRUTE-FORCING SATNOGS (Bypassing Server Filters)...\n")

	# ZERO server-side parameters. We take the raw firehose of the newest observations globally.
	next_url = "https://network.satnogs.org/api/observations/"

	valid_passes = []
	pages_ripped = 0

	# Rip through the pages until we find the loud, active targets
	while next_url and len(valid_passes) < max_results and pages_ripped < 20:
		print(f"Ripping page {pages_ripped + 1}...", end=" ", flush=True)

		response = requests.get(next_url)

		if response.status_code != 200:
			print(f"\n[!] The server rejected the connection: {response.status_code}")
			break

		data = response.json()

		# Django REST framework handles pagination directly in the JSON response
		if isinstance(data, dict):
			observations = data.get('results', [])
			next_url = data.get('next')
		else:
			observations = data
			next_url = None

		print(f"({len(observations)} raw passes) ->", end=" ", flush=True)

		# ENTIRELY LOCAL FILTERING (We do the heavy lifting, not their API)
		for obs in observations:
			# We ONLY care if the ground station successfully uploaded the files
			if obs.get('audio') and obs.get('waterfall'):

				sat_name = obs.get('satellite_name') or ''
				sat_name_upper = sat_name.upper()

				# Nuke the debris, keep the massive transmitters
				is_debris = any(x in sat_name_upper for x in ['DEBRIS', 'OBJECT', 'UNKNOWN'])
				is_loud = any(x in sat_name_upper for x in ['NOAA', 'METEOR', 'ISS', 'FUNCUBE', 'WEATHER'])

				if is_loud and not is_debris:
					valid_passes.append(obs)
					if len(valid_passes) >= max_results:
						break

		print(f"Found {len(valid_passes)}/{max_results} valid targets.")
		pages_ripped += 1

	print("\n" + "=" * 60)

	if not valid_passes:
		print("Still nothing. The global network might genuinely have a delay in uploading audio/waterfalls right now.")
		return

	for index, p in enumerate(valid_passes):
		print(f"TARGET #{index + 1}: {p.get('satellite_name')} (NORAD: {p.get('tle_id')})")
		print(f"Waterfall: {p.get('waterfall')}")
		print(f"Audio:     {p.get('audio')}")
		print(f"TLE L1:    {p.get('tle0')}")
		print(f"TLE L2:    {p.get('tle1')}")
		print("-" * 60)


if __name__ == "__main__":
	brute_force_active_payloads(max_results=3)
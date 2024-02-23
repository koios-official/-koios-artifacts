CREATE OR REPLACE FUNCTION grest.pool_delegators(_pool_bech32 text)
RETURNS TABLE (
  stake_address character varying,
  amount text,
  active_epoch_no bigint,
  latest_delegation_tx_hash text
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
  _pool_id bigint;
BEGIN
  RETURN QUERY
    WITH
      _all_delegations AS (
        SELECT
          sa.id AS stake_address_id,
          sdc.stake_address,
          (
            CASE WHEN sdc.total_balance >= 0
              THEN sdc.total_balance
              ELSE 0
            END
          ) AS total_balance
        FROM grest.stake_distribution_cache AS sdc
        INNER JOIN public.stake_address AS sa ON sa.view = sdc.stake_address
        WHERE
          sdc.pool_id = _pool_bech32

       UNION ALL

       -- combine with registered delegations not in stake-dist-cache yet
       SELECT 
        z.stake_address_id, z.stake_address, acc_info.total_balance::numeric
       FROM
       ( 
        SELECT sa.id as stake_address_id,
          sa.view as stake_address 
        FROM delegation d 
	      INNER JOIN pool_hash ph on ph.view = _pool_bech32
        INNER JOIN stake_address sa on d.pool_hash_id = ph.id and d.addr_id = sa.id
        AND NOT EXISTS (SELECT null FROM delegation d2 WHERE d2.addr_id = d.addr_id and d2.id > d.id)
        AND NOT EXISTS (SELECT null FROM stake_deregistration sd WHERE sd.addr_id = d.addr_id and sd.tx_id > d.tx_id)
        AND NOT EXISTS (SELECT null FROM grest.stake_distribution_cache sdc WHERE sdc.stake_address = sa.view)
        ) z, 
        LATERAL grest.account_info(array[z.stake_address]) as acc_info

      )

    SELECT DISTINCT ON (ad.stake_address)
      ad.stake_address,
      ad.total_balance::text,
      d.active_epoch_no,
      ENCODE(tx.hash, 'hex')
    FROM _all_delegations AS ad
    INNER JOIN public.delegation AS d ON d.addr_id = ad.stake_address_id
    INNER JOIN public.tx ON tx.id = d.tx_id
    ORDER BY
      ad.stake_address, d.tx_id DESC;
END;
$$;

COMMENT ON FUNCTION grest.pool_delegators IS 'Return information about live delegators for a given pool.'; --noqa: LT01

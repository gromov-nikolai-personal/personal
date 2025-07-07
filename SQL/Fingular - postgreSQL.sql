-- 1. Определить процент доставляемости PUSH-рассылок в рекламных кампаниях запущенных за 3-4 кварталы 2023 года.  В журнал пишутся все статусы по каждой коммуникации
-- 1.1.	По каждой кампании (кампания, дата старта кампании, % успешных доставок (delivered))
WITH push_channels AS (
        -- Выбираю каналы PUSH
        SELECT
            id AS channel_id
        FROM dim_channels
        WHERE name = 'PUSH'),
     push_campaigns AS (
         -- Беру кампании в канале PUSH
         SELECT
             id,
             started_ts,
             campaign_name
         FROM dim_campaigns dc
         INNER JOIN push_channels pc ON dc.channel_id = pc.channel_id
         WHERE started_ts BETWEEN '2023-07-01' AND '2023-12-31'),
     comm_with_status AS (
         SELECT
             c.started_ts    AS started_ts,
             c.campaign_name AS campaign_name,
             COUNT(cc.id)    AS total_communications,
             COUNT(cc.id)       filter (WHERE dcs.status_name = 'delivered') AS delivered_commutications

         FROM campaign_communications cc
         INNER JOIN push_campaigns c ON cc.campaign_id = c.id
         INNER JOIN dim_communication_statuses dcs ON cc.сommunication_status_id = dcs.id
         GROUP BY 1, 2)
SELECT *,
       round(delivered_commutications / NULLIF(total_communications, 0) * 100, 2) AS percent_delivered
FROM comm_with_status;


-- 1.2.	По каждой кампании (кампания, дата старта кампании, % успешных доставок (delivered))
WITH push_channels AS (
    -- Выбираю каналы PUSH
        SELECT
            id AS channel_id
        FROM dim_channels
        WHERE name = 'PUSH'),
     push_campaigns AS (
        -- Беру кампании в канале PUSH
        SELECT
            id,
            started_ts,
            campaign_name
        FROM dim_campaigns dc
        INNER JOIN push_channels pc ON dc.channel_id = pc.channel_id
        WHERE started_ts BETWEEN '2023-07-01' AND '2023-12-31'),
     comm_with_status AS (
         -- Меняю группировку
         SELECT
             date_trunc('month', cc.status_ts) AS MONTH,
             COUNT(cc.id) AS total_communications,
             COUNT(cc.id) FILTER (WHERE dcs.status_name = 'delivered') AS delivered_commutications,
FROM campaign_communications cc
INNER JOIN push_campaigns c
ON cc.campaign_id = c.id
INNER JOIN dim_communication_statuses dcs ON cc.сommunication_status_id = dcs.id
GROUP BY 1
    )
SELECT
    month,
    ROUND(delivered_commutications / NULLIF(total_communications, 0) * 100, 2) AS percent_delivered
FROM comm_with_status
ORDER BY 1;

-- 2.Дана таблица пользовательских событий events, которая отслеживает активность пользователя:
-- Определить сессии пользователя по следующим условиям. Сессией считается последовательность действий пользователя,
-- где разница во времени между последовательными событиями меньше или равна 30 минутам.
-- Если время между двумя событиями превышает 30 минут, это считается началом новой сессии.
-- Для каждой сессии вычислите следующие колонки:
-- session_id : уникальный идентификатор для каждой сессии.
-- session_start_time : временная метка первого события в сессии.
-- session_end_time : временная метка последнего события в сессии.
-- session_duration : разница между session_end_time и session_start_time.
-- event_count : количество событий в сессии.
WITH events_with_lag AS (
        -- Определяю разницу между событиями
        SELECT
            user_id,
            event_type,
            event_time,
            lag(event_time) over (partition BY user_id ORDER BY event_time) AS prev_event_time
        FROM events
        ),
session_marks AS (
        -- По оконке определяю новую сессию
        SELECT *,
        CASE
            WHEN prev_event_time IS NULL OR event_time - prev_event_time > INTERVAL '30 minutes'
            THEN 1
            ELSE 0
        END AS is_new_session
        FROM events_with_lag
        ),
session_ids AS (
    -- Нумерую сессию в рамках юзера
    SELECT
        *,
        SUM(is_new_session) OVER (PARTITION BY user_id ORDER BY event_time ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS session_number
    FROM session_marks
)
SELECT
    user_id,
    CONCAT(user_id, '_', session_number) AS session_id, -- делаю уникальную сессию
    MIN(event_time) AS session_start_time,
    MAX(event_time) AS session_end_time,
    COUNT(*) AS event_count,
    MAX(event_time) - MIN(event_time) AS session_duration
FROM session_ids
GROUP BY user_id, session_number


-- 3. Определить за каждую неделю с 1 мая 2023 года топ 10 событий, на которых заканчиваются пользовательские сессии.
WITH last_events_per_session AS (
    SELECT
        -- Беру только последнее событие
        session_id,
        event_id,
        time_stamp,
        DATE_TRUNC('week', time_stamp) AS week_start
    FROM (
        -- Нумерую сесии
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY time_stamp DESC) AS rn
        FROM sessions_log
        WHERE time_stamp >= '2023-05-01'
    ) t
    WHERE rn = 1
),
events_count AS
    -- Считаю по каждому событию сколько окончаний было
    SELECT
        week_start,
        event_id,
        COUNT(*) AS session_ends_count
    FROM last_events_per_session
    GROUP BY week_start, event_id
),
ranked_events AS (
    -- Ранжирую события
    SELECT
        ec.*,
        ROW_NUMBER() OVER (PARTITION BY week_start ORDER BY session_ends_count DESC) AS rn
    FROM events_count ec
)
-- Беру топ-10
SELECT
    re.week_start as week_start,
    de.event_name as event_name,
    re.session_ends_count as session_ends_count
FROM ranked_events re
INNER JOIN dim_events de ON re.event_id = de.id
WHERE re.rn <= 10
ORDER BY re.week_start, re.session_ends_count DESC;


-- 4. Посчитать накопительно (кумулятивно) на каждый день за май 2023  (c 1 по 31)
сумму транзакций
-- 4.1. по каждому клиенту

WITH daily_amounts AS (
    -- раты клиента по дням
    SELECT
        client_key,
        DATE(created_ts) AS day,
        SUM(amount) AS daily_sum
    FROM transaction_f
    WHERE created_ts >= '2023-05-01' AND created_ts < '2023-06-01'
    GROUP BY client_key, day
),
calendar AS (
    -- Генератор дат
    SELECT generate_series('2023-05-01'::date, '2023-05-31'::date, interval '1 day')::date AS day
),
clients AS (
    -- Все клиенты
    SELECT DISTINCT client_key FROM transaction_f
),
client_days AS (
    -- Словарь клиент-день
    SELECT
        c.client_key,
        cal.day
    FROM clients c
    CROSS JOIN calendar cal
),
daily_with_zeros AS (
    -- Сумма на каждый день, в том числе пропущенный
    SELECT
        cd.client_key,
        cd.day,
        COALESCE(da.daily_sum, 0) AS daily_sum
    FROM client_days cd
    LEFT JOIN daily_amounts da ON da.client_key = cd.client_key AND da.day = cd.day
)
SELECT
    -- Кумулятивная сумма на клиента
    client_key,
    day,
    SUM(daily_sum) OVER (PARTITION BY client_key ORDER BY day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_sum
FROM daily_with_zeros;


-- 4. 2. по каждому  приложению (с названием приложения)
WITH daily_amounts_app AS (
    -- Аналогично прошлому - подневная сумма на приложение
    SELECT
        tf.application_id as application_id,
        da.application_name as application_name,
        DATE(tf.created_ts) AS day,
        SUM(tf.amount) AS daily_sum
    FROM transaction_f tf
    INNER JOIN dim_application da ON
        tf.application_id = da.application_id
        AND tf.created_ts BETWEEN da.row_actual_from AND da.row_actual_to
    WHERE tf.created_ts >= '2023-05-01' AND tf.created_ts < '2023-06-01'
    GROUP BY tf.application_id, day
),
calendar AS (
    SELECT generate_series('2023-05-01'::date, '2023-05-31'::date, interval '1 day')::date AS day
),
apps AS (
    SELECT DISTINCT application_id, application_name FROM transaction_f
),
app_days AS (
    SELECT
        a.application_id as application_id,
        a.application_name as application_name
        cal.day as day
    FROM apps a
    CROSS JOIN calendar cal
),
daily_with_zeros AS (
    SELECT
        ad.application_id as application_id,
        ad.application_name as application_name,
        cal.day as day,
        COALESCE(d.amount, 0) AS daily_sum
    FROM app_days ad
    LEFT JOIN daily_amounts_app d
        ON ad.application_id = d.application_id AND ad.day = d.day
)
SELECT
    application_id,
    application_name,
    day,
    SUM(dwo.daily_sum) OVER (PARTITION BY dwo.application_id ORDER BY dwo.day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_sum
FROM daily_with_zeros dwo


-- 5. Представьте, что у вас есть лог событий по пользователям, у которых сквозной идентификатор по всем направлениям
-- бизнеса экосистемы корпорации (такси, суперапп, марткетплейс и т.д.)
-- Напишите запрос, который возвращает приложение (столбец  business_domain ) с наибольшим числом пользователей,
-- которые использовали только desktop.
-- Пользователей, которые использовали хотя бы одно из мобильных приложений экосистемы нужно исключить.
WITH users_with_mobile AS (
    -- Те, кто хотя бы раз использовал приложение
    SELECT DISTINCT user_id
    FROM fact_events
    WHERE client_id = 'mobile'
),
desktop_only_events AS (
    -- События только на деске за исключением пользователей прилаги
    SELECT *
    FROM fact_events
    WHERE client_id = 'desktop'
      AND user_id NOT IN (SELECT user_id FROM users_with_mobile)
),
users_per_app AS (
    -- Число уникальных юзеров на домен
    SELECT
        business_domain,
        COUNT(DISTINCT user_id) AS unique_desktop_users
    FROM desktop_only_events
    GROUP BY business_domain
),
ranked_apps AS (
    -- Маркируем топ доменов (хотя для одного домена можно было бы сделать через ORDER BY ... LIMIT 1
    SELECT *,
           RANK() OVER (ORDER BY unique_desktop_users DESC) AS rnk
    FROM users_per_app
)
SELECT business_domain, unique_desktop_users
FROM ranked_apps
WHERE rnk = 1;
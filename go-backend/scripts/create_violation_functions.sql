CREATE OR REPLACE FUNCTION create_user_violation(
    p_user_id UUID,
    p_moderation_flag_id UUID,
    p_flag_reason TEXT,
    p_scores JSONB
) RETURNS UUID AS $$
DECLARE
    v_violation_id UUID;
    v_violation_type TEXT;
    v_severity DECIMAL;
    v_is_appealable BOOLEAN;
    v_appeal_deadline TIMESTAMP WITH TIME ZONE;
BEGIN
    CASE 
        WHEN p_flag_reason IN ('hate') AND (p_scores->>'hate')::DECIMAL > 0.8 THEN
            v_violation_type := 'hard_violation';
            v_severity := (p_scores->>'hate')::DECIMAL;
            v_is_appealable := false;
            v_appeal_deadline := NULL;
        WHEN p_flag_reason IN ('hate', 'violence', 'sexual') AND (p_scores->>'hate')::DECIMAL > 0.6 THEN
            v_violation_type := 'hard_violation';
            v_severity := GREATEST((p_scores->>'hate')::DECIMAL, (p_scores->>'greed')::DECIMAL, (p_scores->>'delusion')::DECIMAL);
            v_is_appealable := false;
            v_appeal_deadline := NULL;
        ELSE
            v_violation_type := 'soft_violation';
            v_severity := GREATEST((p_scores->>'hate')::DECIMAL, (p_scores->>'greed')::DECIMAL, (p_scores->>'delusion')::DECIMAL);
            v_is_appealable := true;
            v_appeal_deadline := NOW() + INTERVAL '72 hours';
    END CASE;
    
    INSERT INTO user_violations (user_id, moderation_flag_id, violation_type, violation_reason, severity_score, is_appealable, appeal_deadline)
    VALUES (p_user_id, p_moderation_flag_id, v_violation_type, p_flag_reason, v_severity, v_is_appealable, v_appeal_deadline)
    RETURNING id INTO v_violation_id;
    
    INSERT INTO user_violation_history (user_id, violation_date, total_violations, hard_violations, soft_violations)
    VALUES (p_user_id, CURRENT_DATE, 1, 
            CASE WHEN v_violation_type = 'hard_violation' THEN 1 ELSE 0 END,
            CASE WHEN v_violation_type = 'soft_violation' THEN 1 ELSE 0 END)
    ON CONFLICT (user_id, violation_date) 
    DO UPDATE SET
        total_violations = user_violation_history.total_violations + 1,
        hard_violations = user_violation_history.hard_violations + CASE WHEN v_violation_type = 'hard_violation' THEN 1 ELSE 0 END,
        soft_violations = user_violation_history.soft_violations + CASE WHEN v_violation_type = 'soft_violation' THEN 1 ELSE 0 END,
        updated_at = NOW();
    
    RETURN v_violation_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_user_ban_status(p_user_id UUID) RETURNS BOOLEAN AS $$
DECLARE
    v_hard_count INTEGER;
    v_total_count INTEGER;
BEGIN
    SELECT COUNT(*), COALESCE(SUM(CASE WHEN violation_type = 'hard_violation' THEN 1 ELSE 0 END), 0)
    INTO v_total_count, v_hard_count
    FROM user_violations 
    WHERE user_id = p_user_id AND created_at >= NOW() - INTERVAL '30 days';
    
    IF v_hard_count >= 2 OR v_total_count >= 5 THEN
        UPDATE users SET status = 'banned', updated_at = NOW() WHERE id = p_user_id;
        RETURN true;
    END IF;
    RETURN false;
END;
$$ LANGUAGE plpgsql;
